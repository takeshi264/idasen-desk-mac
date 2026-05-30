import CoreBluetooth
import Foundation

struct DiscoveredDesk: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isConnected: Bool
}

final class BluetoothManager: NSObject {
    static let shared = BluetoothManager()

    var centralManager: CBCentralManager?

    var onCentralManagerStateChange: (CBCentralManager?) -> Void = { _ in }
    var onConnectedPeripheralsChange: ([CBPeripheral]) -> Void = { _ in }
    var onDiscoveredDesksChange: ([DiscoveredDesk]) -> Void = { _ in }
    var onDiscoveryScanningChange: (Bool) -> Void = { _ in }

    private var connectedPeripherals = [UUID: CBPeripheral]() {
        didSet {
            onConnectedPeripheralsChange(connectedPeripherals.values.sortedByName)
            publishDiscoveredDesks()
        }
    }
    private var connectingIDs = Set<UUID>()

    private var discoveredPeripherals = [UUID: CBPeripheral]() {
        didSet {
            publishDiscoveredDesks()
        }
    }

    private var discoveredRSSI = [UUID: Int]() {
        didSet {
            publishDiscoveredDesks()
        }
    }

    private var cachedPeripherals = [UUID: CBPeripheral]()
    private var discoveryStopTimer: Timer?
    private var connectionTimeoutTimers = [UUID: Timer]()

    private(set) var isDiscoveryScanning = false {
        didSet {
            guard isDiscoveryScanning != oldValue else {
                return
            }

            onDiscoveryScanningChange(isDiscoveryScanning)
        }
    }

    var connectedDeskPeripherals: [CBPeripheral] {
        connectedPeripherals.values.sortedByName
    }

    var discoveredDesks: [DiscoveredDesk] {
        discoveredPeripherals.values
            .map { peripheral in
                DiscoveredDesk(
                    id: peripheral.identifier,
                    name: displayName(for: peripheral),
                    rssi: discoveredRSSI[peripheral.identifier] ?? 0,
                    isConnected: connectedPeripherals[peripheral.identifier] != nil
                )
            }
            .sorted { first, second in
                if first.isConnected != second.isConnected {
                    return first.isConnected
                }

                return first.rssi > second.rssi
            }
    }

    override init() {
        super.init()
        prepare()
    }

    func prepare() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    func connectKnownDesks(ids: [UUID]) {
        guard let centralManager, centralManager.state == .poweredOn, !ids.isEmpty else {
            return
        }

        let connectedIDs = Set(connectedPeripherals.keys)
        let idsToConnect = ids.filter { !connectedIDs.contains($0) }
        guard !idsToConnect.isEmpty else {
            return
        }

        let retrievedPeripherals = centralManager.retrievePeripherals(withIdentifiers: idsToConnect)
        for peripheral in retrievedPeripherals where connectedPeripherals[peripheral.identifier] == nil {
            connect(peripheral)
        }
    }

    func startDiscovery(duration: TimeInterval = 20) {
        prepare()

        guard let centralManager, centralManager.state == .poweredOn else {
            return
        }

        discoveryStopTimer?.invalidate()
        isDiscoveryScanning = true

        if !centralManager.isScanning {
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        let timer = Timer(fire: Date().addingTimeInterval(duration), interval: 0, repeats: false) { [weak self] _ in
            self?.stopDiscovery()
        }
        timer.tolerance = 1
        discoveryStopTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopDiscovery() {
        discoveryStopTimer?.invalidate()
        discoveryStopTimer = nil
        isDiscoveryScanning = false
        centralManager?.stopScan()
    }

    func connectToDesk(id: UUID) {
        guard let centralManager, centralManager.state == .poweredOn else {
            return
        }

        if let peripheral = connectedPeripherals[id] {
            if peripheral.state == .disconnected, !connectingIDs.contains(id) {
                connect(peripheral)
            }
            return
        }

        if let peripheral = discoveredPeripherals[id] ?? cachedPeripherals[id] {
            connect(peripheral)
            return
        }

        let retrieved = centralManager.retrievePeripherals(withIdentifiers: [id])
        if let peripheral = retrieved.first {
            connect(peripheral)
        }
    }

    func disconnectDesk(id: UUID) {
        guard let peripheral = connectedPeripherals[id] ?? discoveredPeripherals[id] ?? cachedPeripherals[id] else {
            return
        }

        clearConnectionAttempt(for: id)
        connectedPeripherals[id] = nil
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func reconnect(id: UUID?) {
        if let id {
            connectToDesk(id: id)
            return
        }

        for peripheral in connectedPeripherals.values where peripheral.state == .disconnected {
            centralManager?.connect(peripheral, options: nil)
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        centralManager = central
        onCentralManagerStateChange(central)

        guard central.state == .poweredOn else {
            clearConnectionAttempts()
            connectedPeripherals.removeAll()
            discoveredPeripherals.removeAll()
            discoveredRSSI.removeAll()
            cachedPeripherals.removeAll()
            stopDiscovery()
            return
        }

        if isDiscoveryScanning {
            startDiscovery()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard matchesDesk(peripheral: peripheral, advertisementData: advertisementData) else {
            return
        }

        discoveredPeripherals[peripheral.identifier] = peripheral
        cachedPeripherals[peripheral.identifier] = peripheral
        discoveredRSSI[peripheral.identifier] = RSSI.intValue
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        clearConnectionAttempt(for: peripheral.identifier)
        cachedPeripherals[peripheral.identifier] = peripheral
        connectedPeripherals[peripheral.identifier] = peripheral
        stopDiscovery()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        clearConnectionAttempt(for: peripheral.identifier)
        connectedPeripherals[peripheral.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        clearConnectionAttempt(for: peripheral.identifier)
        connectedPeripherals[peripheral.identifier] = nil
    }
}

private extension BluetoothManager {
    func connect(_ peripheral: CBPeripheral) {
        guard let centralManager, centralManager.state == .poweredOn else {
            return
        }

        guard connectedPeripherals[peripheral.identifier] == nil,
              !connectingIDs.contains(peripheral.identifier) else {
            return
        }

        cachedPeripherals[peripheral.identifier] = peripheral
        connectingIDs.insert(peripheral.identifier)
        scheduleConnectionTimeout(for: peripheral)
        centralManager.connect(peripheral, options: nil)
    }

    func scheduleConnectionTimeout(for peripheral: CBPeripheral) {
        let id = peripheral.identifier
        connectionTimeoutTimers[id]?.invalidate()

        let timer = Timer(fire: Date().addingTimeInterval(10), interval: 0, repeats: false) { [weak self, weak peripheral] _ in
            guard let self,
                  self.connectingIDs.contains(id) else {
                return
            }

            self.clearConnectionAttempt(for: id)

            if let peripheral {
                self.centralManager?.cancelPeripheralConnection(peripheral)
            }

            self.publishDiscoveredDesks()
        }

        timer.tolerance = 1
        connectionTimeoutTimers[id] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func clearConnectionAttempt(for id: UUID) {
        connectingIDs.remove(id)
        connectionTimeoutTimers[id]?.invalidate()
        connectionTimeoutTimers[id] = nil
    }

    func clearConnectionAttempts() {
        connectingIDs.removeAll()
        connectionTimeoutTimers.values.forEach { $0.invalidate() }
        connectionTimeoutTimers.removeAll()
    }

    func matchesDesk(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           serviceUUIDs.contains(DeskPeripheral.deskPositionServiceUUID) ||
           serviceUUIDs.contains(DeskPeripheral.deskControlServiceUUID) {
            return true
        }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let names = [peripheral.name, advertisedName].compactMap { $0 }

        return names.contains { name in
            name.localizedCaseInsensitiveContains("desk") ||
            name.localizedCaseInsensitiveContains("idasen")
        }
    }

    func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "IDASEN Desk"
    }

    func publishDiscoveredDesks() {
        onDiscoveredDesksChange(discoveredDesks)
    }
}

private extension Collection where Element == CBPeripheral {
    var sortedByName: [CBPeripheral] {
        sorted {
            let firstName = $0.name ?? ""
            let secondName = $1.name ?? ""
            let nameOrder = firstName.localizedCaseInsensitiveCompare(secondName)

            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return $0.identifier.uuidString < $1.identifier.uuidString
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
