import AppKit
import CoreBluetooth
import Observation
import os

struct DiscoveredDesk: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isKnown: Bool
}

/// Owns Bluetooth, keeps the remembered desk connected, and is the single entry point
/// for moving it. Everything the UI shows about the desk comes from here.
@MainActor
@Observable
final class DeskManager {
    enum Status: Equatable {
        case starting
        case bluetoothOff
        case unauthorized
        case unsupported
        /// No desk has been set up yet.
        case noDesk
        /// Waiting for a remembered desk to come into range.
        case searching
        case connecting
        case connected
    }

    enum MoveTarget: Equatable {
        case preset(PresetID)
        case height(Double)
    }

    private(set) var status: Status = .starting
    private(set) var heightRaw: Int?
    private(set) var direction: MovingDirection = .none
    private(set) var target: MoveTarget?
    private(set) var isJogging = false
    private(set) var connectedDeskID: UUID?
    private(set) var discoveredDesks = [DiscoveredDesk]()
    private(set) var isScanning = false
    /// Set when a move ended away from its target, cleared on the next move.
    private(set) var lastMoveStalled = false

    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private let centralDelegate = CentralDelegate()
    @ObservationIgnored private var connection: DeskConnection?
    @ObservationIgnored private var peripherals = [UUID: CBPeripheral]()
    @ObservationIgnored private var pendingIDs = Set<UUID>()
    @ObservationIgnored private var requestedDeskID: UUID?
    @ObservationIgnored private var discovered = [UUID: DiscoveredDesk]()
    @ObservationIgnored private let scanTimeout = DelayedTask()
    @ObservationIgnored private let secondaryConnect = DelayedTask()
    @ObservationIgnored private let retry = DelayedTask()
    @ObservationIgnored private let gestureMove = DelayedTask()
    @ObservationIgnored private var observers = [NSObjectProtocol]()

    private static let logger = Logger(subsystem: "com.takeshi264.idasen-desk-mac", category: "bluetooth")

    init(preferences: Preferences, startsBluetooth: Bool = true) {
        self.preferences = preferences

        guard startsBluetooth else {
            return
        }

        centralDelegate.owner = self
        central = CBCentralManager(
            delegate: centralDelegate,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemDidWake()
            }
        })
    }

    // MARK: - Reading

    var geometry: DeskGeometry {
        preferences.geometry
    }

    var height: Double? {
        heightRaw.map(geometry.height(raw:))
    }

    var isConnected: Bool {
        status == .connected
    }

    var isMoving: Bool {
        target != nil || isJogging || direction != .none
    }

    var deskName: String? {
        preferences.deskName(for: connectedDeskID ?? preferences.activeDeskID)
    }

    /// The preset the desk is currently resting at, if any.
    var currentPreset: PresetID? {
        guard let height, direction == .none else {
            return nil
        }

        let presets: [PresetID] = [.sit, .stand] + preferences.customPresets.map { .custom($0.id) }
        return presets.first { preset in
            preferences.height(for: preset).map { abs($0 - height) <= 0.6 } ?? false
        }
    }

    // MARK: - Moving

    func move(to preset: PresetID) {
        guard let height = preferences.height(for: preset) else {
            return
        }

        startMove(toHeight: height, target: .preset(preset))
    }

    func move(toHeight height: Double) {
        startMove(toHeight: height, target: .height(height))
    }

    /// Menu bar buttons: a second click on the preset being driven to stops the desk.
    func moveOrStop(_ preset: PresetID) {
        if target == .preset(preset) {
            stop()
        } else {
            move(to: preset)
        }
    }

    func toggleSitStand() {
        if isMoving {
            stop()
            return
        }

        guard let height else {
            return
        }

        let midpoint = (preferences.sittingHeight + preferences.standingHeight) / 2
        move(to: height < midpoint ? .stand : .sit)
    }

    func nudge(_ direction: MovingDirection, by centimeters: Double = 1) {
        guard let height, direction != .none else {
            return
        }

        move(toHeight: height + (direction == .up ? centimeters : -centimeters))
    }

    func startJog(_ direction: MovingDirection) {
        target = nil
        lastMoveStalled = false
        isJogging = connection?.isReady == true
        connection?.startJog(direction)
    }

    func stopJog() {
        guard isJogging else {
            return
        }

        stop()
    }

    func stop() {
        gestureMove.cancel()
        connection?.stop()
        target = nil
        isJogging = false
    }

    private func startMove(toHeight height: Double, target: MoveTarget) {
        guard let connection, connection.isReady else {
            return
        }

        lastMoveStalled = false
        isJogging = false
        self.target = target
        connection.move(toRaw: geometry.raw(height: height))
        syncFromConnection()
    }

    /// Used by Shortcuts and AppleScript, which may run right after launch.
    func waitUntilReady(timeout: Duration = .seconds(15)) async -> Bool {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if status == .connected {
                return true
            }
            ensureConnecting()
            try? await Task.sleep(for: .milliseconds(250))
        }

        return status == .connected
    }

    // MARK: - Desks

    func startScan(duration: Duration = .seconds(30)) {
        guard let central, central.state == .poweredOn else {
            return
        }

        discovered.removeAll()
        publishDiscovered()

        if !central.isScanning {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }

        isScanning = true
        scanTimeout.schedule(after: duration) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        scanTimeout.cancel()
        central?.stopScan()
        isScanning = false
    }

    /// Connects to a specific desk, dropping the current one if needed.
    func connect(to id: UUID) {
        guard let central, central.state == .poweredOn, connectedDeskID != id else {
            return
        }

        requestedDeskID = id
        preferences.activeDeskID = preferences.knownDesks.contains { $0.id == id } ? id : preferences.activeDeskID

        for pendingID in pendingIDs where pendingID != id {
            cancelConnection(pendingID)
        }

        guard let peripheral = peripheral(for: id) else {
            startScan()
            return
        }

        connect(peripheral)
        updateStatus()
    }

    func forget(_ id: UUID) {
        if requestedDeskID == id {
            requestedDeskID = nil
        }

        preferences.forgetDesk(id: id)
        cancelConnection(id)
        updateStatus()
    }

    // MARK: - Connection lifecycle

    private func ensureConnecting() {
        guard let central, central.state == .poweredOn, connection == nil else {
            updateStatus()
            return
        }

        let ids: [UUID]
        if let requestedDeskID {
            ids = [requestedDeskID]
        } else {
            let known = preferences.knownDesks.map(\.id)
            let preferred = preferences.activeDeskID.flatMap { known.contains($0) ? $0 : nil }
            ids = (preferred.map { [$0] } ?? []) + known.filter { $0 != preferred }
        }

        guard let first = ids.first else {
            updateStatus()
            return
        }

        if let peripheral = peripheral(for: first) {
            connect(peripheral)
        } else if !isScanning {
            // Not in the system cache any more; it has to be found by advertisement.
            startScan(duration: .seconds(60))
        }

        // Other remembered desks (say, home and office) get a moment later, so the
        // preferred one wins when both are in range.
        let others = ids.dropFirst()
        if !others.isEmpty, !secondaryConnect.isPending {
            secondaryConnect.schedule(after: .seconds(4)) { [weak self] in
                guard let self, self.connection == nil else {
                    return
                }

                for id in others {
                    if let peripheral = self.peripheral(for: id) {
                        self.connect(peripheral)
                    }
                }
            }
        }

        updateStatus()
    }

    private func peripheral(for id: UUID) -> CBPeripheral? {
        if let peripheral = peripherals[id] {
            return peripheral
        }

        guard let peripheral = central?.retrievePeripherals(withIdentifiers: [id]).first else {
            return nil
        }

        peripherals[id] = peripheral
        return peripheral
    }

    /// Connection requests never time out: CoreBluetooth completes them whenever the
    /// desk shows up, which is exactly what reconnecting after sleep or travel needs.
    private func connect(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard !pendingIDs.contains(id), peripheral.state != .connected, connection?.id != id else {
            return
        }

        peripherals[id] = peripheral
        pendingIDs.insert(id)
        central?.connect(peripheral)
    }

    private func cancelConnection(_ id: UUID) {
        pendingIDs.remove(id)
        if let peripheral = peripherals[id] {
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    private func systemDidWake() {
        guard connection == nil else {
            return
        }

        // Pending requests can go stale across sleep; issue fresh ones.
        for id in pendingIDs {
            cancelConnection(id)
        }

        retry.schedule(after: .seconds(2)) { [weak self] in
            self?.ensureConnecting()
        }
    }

    fileprivate func centralDidUpdateState() {
        guard let central else {
            return
        }

        Self.logger.info("Bluetooth state \(central.state.rawValue)")

        if central.state == .poweredOn {
            ensureConnecting()
        } else {
            connection = nil
            pendingIDs.removeAll()
            isScanning = false
            clearDeskState()
        }

        updateStatus()
    }

    fileprivate func didDiscover(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi: Int) {
        let advertisedName = advertisement[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = advertisedName ?? peripheral.name

        guard DeskProtocol.looksLikeDesk(name: name, advertisedServices: services) else {
            return
        }

        let id = peripheral.identifier
        let isKnown = preferences.knownDesks.contains { $0.id == id }
        peripherals[id] = peripheral

        if id != connectedDeskID {
            discovered[id] = DiscoveredDesk(id: id, name: name ?? "IDASEN Desk", rssi: rssi, isKnown: isKnown)
            publishDiscovered()
        }

        if connection == nil, isKnown || requestedDeskID == id {
            connect(peripheral)
        }
    }

    fileprivate func didConnect(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        pendingIDs.remove(id)

        if let current = connection, current.id != id {
            guard requestedDeskID == id else {
                central?.cancelPeripheralConnection(peripheral)
                return
            }

            current.stop()
            central?.cancelPeripheralConnection(current.peripheral)
        }

        Self.logger.info("Connected to \(id, privacy: .public)")

        for otherID in pendingIDs {
            cancelConnection(otherID)
        }
        secondaryConnect.cancel()
        retry.cancel()
        requestedDeskID = nil

        let connection = DeskConnection(peripheral: peripheral)
        connection.onChange = { [weak self, weak connection] in
            guard let self, let connection, self.connection === connection else {
                return
            }
            self.syncFromConnection()
        }
        connection.onMoveFinished = { [weak self] outcome in
            self?.lastMoveStalled = outcome == .stalled || outcome == .timedOut
            self?.target = nil
        }
        connection.onHandleDoubleTap = { [weak self] direction in
            self?.handleDoubleTap(direction)
        }

        self.connection = connection
        connectedDeskID = id
        preferences.rememberDesk(id: id, name: peripheral.name)
        discovered[id] = nil
        publishDiscovered()

        if isScanning {
            stopScan()
        }

        connection.discover()
        syncFromConnection()
    }

    fileprivate func didDisconnect(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        pendingIDs.remove(id)

        if connection?.id == id {
            Self.logger.info("Disconnected from \(id, privacy: .public)")
            connection = nil
            clearDeskState()
        }

        ensureConnecting()
    }

    fileprivate func didFailToConnect(_ peripheral: CBPeripheral) {
        pendingIDs.remove(peripheral.identifier)
        retry.schedule(after: .seconds(3)) { [weak self] in
            self?.ensureConnecting()
        }
    }

    private func handleDoubleTap(_ direction: MovingDirection) {
        guard preferences.doubleTapToSitStand else {
            return
        }

        gestureMove.schedule(after: .milliseconds(250)) { [weak self] in
            self?.move(to: direction == .up ? .stand : .sit)
        }
    }

    private func syncFromConnection() {
        guard let connection else {
            return
        }

        heightRaw = connection.report?.raw
        direction = connection.direction

        if connection.motion == .idle {
            target = nil
            isJogging = false
        }

        updateStatus()
    }

    private func clearDeskState() {
        connectedDeskID = nil
        heightRaw = nil
        direction = .none
        target = nil
        isJogging = false
    }

    private func publishDiscovered() {
        discoveredDesks = discovered.values.sorted { $0.rssi > $1.rssi }
    }

    private func updateStatus() {
        let newStatus: Status

        if CBManager.authorization == .denied || CBManager.authorization == .restricted {
            newStatus = .unauthorized
        } else {
            switch central?.state {
            case .poweredOn:
                if let connection {
                    newStatus = connection.isReady ? .connected : .connecting
                } else if preferences.knownDesks.isEmpty && requestedDeskID == nil {
                    newStatus = .noDesk
                } else {
                    newStatus = .searching
                }
            case .poweredOff:
                newStatus = .bluetoothOff
            case .unauthorized:
                newStatus = .unauthorized
            case .unsupported:
                newStatus = .unsupported
            default:
                newStatus = .starting
            }
        }

        if status != newStatus {
            status = newStatus
        }
    }

    #if DEBUG
    /// Drives the UI without hardware, for rendering screenshots.
    func setPreviewState(status: Status, heightRaw: Int?, target: MoveTarget? = nil, direction: MovingDirection = .none, discovered: [DiscoveredDesk] = [], isScanning: Bool = false) {
        self.status = status
        self.heightRaw = heightRaw
        self.target = target
        self.direction = direction
        self.discoveredDesks = discovered
        self.isScanning = isScanning
        self.connectedDeskID = status == .connected ? preferences.knownDesks.first?.id : nil
    }
    #endif
}

/// CoreBluetooth needs an NSObject delegate; this forwards to the main-actor manager.
private final class CentralDelegate: NSObject, CBCentralManagerDelegate {
    weak var owner: DeskManager?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            owner?.centralDidUpdateState()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            owner?.didDiscover(peripheral, advertisement: advertisementData, rssi: RSSI.intValue)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            owner?.didConnect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            owner?.didDisconnect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            owner?.didFailToConnect(peripheral)
        }
    }
}
