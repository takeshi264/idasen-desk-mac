import AppKit
import CoreBluetooth
import SwiftUI

@MainActor
final class DeskAppModel: ObservableObject {
    struct DeskSummary: Identifiable, Equatable {
        let id: UUID
        let name: String
        let isActive: Bool
        let height: Float?
        let direction: MovingDirection
    }

    @Published private(set) var connectionState: CBManagerState = .unknown
    @Published private(set) var peripheralName = ""
    @Published private(set) var deskPosition: Float?
    @Published private(set) var movingDirection: MovingDirection = .none
    @Published private(set) var movingToPosition: Position?
    @Published private(set) var activeDeskID: UUID?
    @Published private(set) var connectedDesks = [DeskSummary]()
    @Published private(set) var discoveredDesks = [DiscoveredDesk]()
    @Published private(set) var isScanningForDesks = false

    private let bluetoothManager = BluetoothManager.shared
    private let healthStats = HealthStatsStore.shared
    private var controllers = [UUID: DeskMotionController]()

    init() {
        bluetoothManager.onCentralManagerStateChange = { [weak self] centralManager in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.connectionState = centralManager?.state ?? .unknown

                if centralManager?.state == .poweredOn {
                    self.connectSavedDesks()
                    self.activeController?.autoStand.update()
                } else {
                    self.controllers.values.forEach { $0.autoStand.unschedule() }
                }
            }
        }

        bluetoothManager.onConnectedPeripheralsChange = { [weak self] peripherals in
            Task { @MainActor in
                self?.configureControllers(for: peripherals)
            }
        }

        bluetoothManager.onDiscoveredDesksChange = { [weak self] desks in
            Task { @MainActor in
                self?.discoveredDesks = desks
            }
        }

        bluetoothManager.onDiscoveryScanningChange = { [weak self] isScanning in
            Task { @MainActor in
                self?.isScanningForDesks = isScanning
            }
        }

        connectionState = bluetoothManager.centralManager?.state ?? .unknown
        discoveredDesks = bluetoothManager.discoveredDesks
        isScanningForDesks = bluetoothManager.isDiscoveryScanning
        configureControllers(for: bluetoothManager.connectedDeskPeripherals)
    }

    var isConnected: Bool {
        activeController != nil
    }

    var statusTitle: String {
        switch connectionState {
        case .poweredOn:
            if isConnected {
                return connectedDesks.count > 1 ? "\(connectedDesks.count) desks" : "Connected"
            }

            if isScanningForDesks {
                return "Scanning"
            }

            return Preferences.shared.knownDesks.isEmpty ? "Set up" : "Ready"
        case .poweredOff:
            return "Bluetooth Off"
        case .resetting:
            return "Reconnecting"
        case .unauthorized:
            return "Unauthorized"
        case .unsupported:
            return "Unsupported"
        case .unknown:
            return "Starting"
        @unknown default:
            return "Unknown"
        }
    }

    var statusColor: Color {
        switch connectionState {
        case .poweredOn:
            return isConnected ? .green : .orange
        case .resetting, .unknown:
            return .orange
        default:
            return .red
        }
    }

    func reconnect() {
        if let activeDeskID {
            bluetoothManager.reconnect(id: activeDeskID)
        } else {
            connectSavedDesks()
        }
    }

    func startDeskDiscovery() {
        bluetoothManager.startDiscovery()
    }

    func stopDeskDiscovery() {
        bluetoothManager.stopDiscovery()
    }

    func connectToDesk(id: UUID) {
        bluetoothManager.connectToDesk(id: id)
    }

    func disconnectDesk(id: UUID) {
        if activeDeskID == id {
            controllers[id]?.stopMoving()
        }

        bluetoothManager.disconnectDesk(id: id)
    }

    func makeActiveDesk(id: UUID) {
        guard controllers[id] != nil else {
            Preferences.shared.activeDeskID = id
            bluetoothManager.connectToDesk(id: id)
            return
        }

        activateController(id: id)
    }

    func forgetDesk(id: UUID) {
        let wasActive = activeDeskID == id
        let nextConnectedID = connectedDesks.first { $0.id != id }?.id

        Preferences.shared.forgetDesk(id: id)

        if controllers[id] != nil {
            disconnectDesk(id: id)
        }

        if wasActive {
            activateController(id: nextConnectedID)
        }

        updateDeskSummaries()
    }

    func moveUp() {
        activeController?.moveUp()
    }

    func moveDown() {
        activeController?.moveDown()
    }

    func stopMoving() {
        activeController?.stopMoving()
    }

    func moveToSitOrStop() {
        if movingToPosition == .sit {
            stopMoving()
        } else {
            activeController?.moveToPosition(.sit)
        }
    }

    func moveToStandOrStop() {
        if movingToPosition == .stand {
            stopMoving()
        } else {
            activeController?.moveToPosition(.stand)
        }
    }

    private var activeController: DeskMotionController? {
        guard let activeDeskID else {
            return nil
        }

        return controllers[activeDeskID]
    }

    private func connectSavedDesks() {
        let preferences = Preferences.shared
        let preferredID = preferences.activeDeskID ?? preferences.knownDesks.first?.id
        guard let preferredID else { return }
        bluetoothManager.connectKnownDesks(ids: [preferredID])
    }

    private func configureControllers(for peripherals: [CBPeripheral]) {
        let liveIDs = Set(peripherals.map(\.identifier))

        for id in Array(controllers.keys) where !liveIDs.contains(id) {
            controllers[id]?.resignActive()
            controllers[id] = nil
        }

        for peripheral in peripherals where controllers[peripheral.identifier] == nil {
            configureController(for: peripheral)
        }

        if let preferredID = Preferences.shared.activeDeskID, controllers[preferredID] != nil {
            activateController(id: preferredID)
        } else {
            activateController(id: fallbackConnectedDeskID())
        }

        updateDeskSummaries()
    }

    private func configureController(for peripheral: CBPeripheral) {
        let deskID = peripheral.identifier
        let name = peripheral.name ?? Preferences.shared.knownDesks.first(where: { $0.id == deskID })?.name ?? "IDASEN Desk"
        Preferences.shared.rememberDesk(id: deskID, name: name)

        let desk = DeskPeripheral(peripheral: peripheral)
        let controller = DeskMotionController(desk: desk)
        controllers[deskID] = controller

        controller.onPositionChange { [weak self] _ in
            Task { @MainActor in
                self?.updateActiveState()
                self?.updateDeskSummaries()
            }
        }

        controller.onCurrentMovingDirectionChange = { [weak self] direction in
            Task { @MainActor in
                guard self?.activeDeskID == deskID else {
                    self?.updateDeskSummaries()
                    return
                }

                self?.movingDirection = direction
                self?.updateDeskSummaries()
            }
        }

        controller.onMovingToPositionChange = { [weak self] position in
            Task { @MainActor in
                guard self?.activeDeskID == deskID else {
                    return
                }

                self?.movingToPosition = position
            }
        }

        controller.onDoubleTapDetected = { [weak self] direction in
            Task { @MainActor in
                guard Preferences.shared.doubleTapToSitStand,
                      self?.activeDeskID == deskID,
                      let controller = self?.controllers[deskID] else {
                    return
                }

                switch direction {
                case .up:
                    controller.moveToPositionAfterSwitchGesture(.stand)
                case .down:
                    controller.moveToPositionAfterSwitchGesture(.sit)
                case .none:
                    break
                }
            }
        }
    }

    private func activateController(id: UUID?) {
        if let id, activeDeskID == id, let controller = controllers[id], DeskMotionController.shared === controller {
            updateActiveState()
            updateDeskSummaries()
            return
        }

        controllers.values.forEach { $0.resignActive() }

        guard let id, let controller = controllers[id] else {
            activeDeskID = nil

            if Preferences.shared.knownDesks.isEmpty {
                Preferences.shared.activeDeskID = nil
            }

            peripheralName = ""
            deskPosition = nil
            movingDirection = .none
            movingToPosition = nil
            healthStats.endSession()
            updateDeskSummaries()
            return
        }

        activeDeskID = id
        Preferences.shared.activeDeskID = id
        controller.becomeActive()
        updateActiveState()
        updateDeskSummaries()
    }

    private func fallbackConnectedDeskID() -> UUID? {
        if let activeDeskID, controllers[activeDeskID] != nil {
            return activeDeskID
        }

        for desk in Preferences.shared.knownDesks where controllers[desk.id] != nil {
            return desk.id
        }

        return controllers.keys.sorted { firstID, secondID in
            let firstName = controllers[firstID]?.desk.peripheral.name ?? ""
            let secondName = controllers[secondID]?.desk.peripheral.name ?? ""
            let nameOrder = firstName.localizedCaseInsensitiveCompare(secondName)

            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return firstID.uuidString < secondID.uuidString
        }.first
    }

    private func updateActiveState() {
        guard let activeDeskID, let controller = controllers[activeDeskID] else {
            return
        }

        peripheralName = Preferences.shared.knownDesks.first(where: { $0.id == activeDeskID })?.name ?? "IDASEN Desk"
        deskPosition = controller.desk.position
        movingDirection = controller.currentMovingDirection
        movingToPosition = controller.movingToPosition

        healthStats.recordActiveDesk(
            id: activeDeskID,
            name: peripheralName,
            height: controller.desk.position,
            sittingHeight: Preferences.shared.sittingPosition,
            standingHeight: Preferences.shared.standingPosition
        )
    }

    private func updateDeskSummaries() {
        connectedDesks = controllers.map { id, controller in
            DeskSummary(
                id: id,
                name: Preferences.shared.knownDesks.first(where: { $0.id == id })?.name ?? "IDASEN Desk",
                isActive: id == activeDeskID,
                height: controller.desk.position,
                direction: controller.currentMovingDirection
            )
        }
        .sorted { first, second in
            if first.isActive != second.isActive {
                return first.isActive
            }

            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }
}

struct DeskControlView: View {
    @ObservedObject var model: DeskAppModel
    @ObservedObject var preferences: Preferences
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DeskMark(statusColor: model.statusColor, direction: model.movingDirection)

                VStack(alignment: .leading, spacing: 1) {
                    Text("IDASEN Desk")
                        .font(.headline)
                    Text(model.peripheralName.isEmpty ? model.statusTitle : "\(model.statusTitle) - \(model.peripheralName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if preferences.doubleTapToSitStand {
                    DoubleTapStatusIndicator(isConnected: model.isConnected)
                }

                MovementChip(direction: model.movingDirection, movingToPosition: model.movingToPosition)
            }

            if model.connectedDesks.count > 1 {
                DeskSwitcherStrip(desks: model.connectedDesks, select: model.makeActiveDesk(id:))
            }

            if !model.isConnected && preferences.knownDesks.isEmpty {
                FirstRunGuide(
                    isScanning: model.isScanningForDesks,
                    startDiscovery: model.startDeskDiscovery,
                    openSettings: {
                        openWindow(id: "preferences")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }

            HeightHero(
                height: liveHeight,
                unit: unit,
                direction: model.movingDirection,
                statusColor: model.statusColor,
                sittingHeight: sittingHeight,
                standingHeight: standingHeight
            )

            HStack(spacing: 10) {
                TargetButton(
                    title: model.movingToPosition == .sit ? "Stop" : "Sit",
                    subtitle: "\(formatted(sittingHeight)) \(unit)",
                    systemImage: "chair",
                    isActive: model.movingToPosition == .sit,
                    tint: .blue,
                    action: model.moveToSitOrStop
                )
                .disabled(!model.isConnected)

                TargetButton(
                    title: model.movingToPosition == .stand ? "Stop" : "Stand",
                    subtitle: "\(formatted(standingHeight)) \(unit)",
                    systemImage: "figure.stand",
                    isActive: model.movingToPosition == .stand,
                    tint: .green,
                    action: model.moveToStandOrStop
                )
                .disabled(!model.isConnected)
            }

            HStack(spacing: 10) {
                JogButton(systemImage: "arrow.down", title: "Move down") {
                    model.moveDown()
                } stop: {
                    model.stopMoving()
                }

                JogButton(systemImage: "arrow.up", title: "Move up") {
                    model.moveUp()
                } stop: {
                    model.stopMoving()
                }
            }

            HStack(spacing: 8) {
                FooterButton(
                    title: model.isConnected ? "Reconnect" : "Find Desk",
                    systemImage: model.isConnected ? "arrow.clockwise" : "dot.radiowaves.left.and.right",
                    action: model.isConnected ? model.reconnect : model.startDeskDiscovery
                )

                Spacer(minLength: 0)

                FooterButton(title: "Settings", systemImage: "gearshape") {
                    openWindow(id: "preferences")
                    NSApp.activate(ignoringOtherApps: true)
                }

                FooterButton(title: "Quit", systemImage: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 364, height: popoverHeight, alignment: .topLeading)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        Color.clear,
                        Color.green.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var unit: String {
        preferences.isMetric ? "cm" : "in"
    }

    private var popoverHeight: CGFloat {
        model.connectedDesks.count > 1 || (!model.isConnected && preferences.knownDesks.isEmpty) ? 456 : 386
    }

    private var liveHeight: Double? {
        guard var position = model.deskPosition else {
            return nil
        }

        position += preferences.positionOffset
        return displayLiveHeight(position)
    }

    private var sittingHeight: Double {
        Double(displayHeight(preferences.sittingPosition))
    }

    private var standingHeight: Double {
        Double(displayHeight(preferences.standingPosition))
    }

    private func displayHeight(_ centimeters: Float) -> Float {
        preferences.isMetric ? centimeters : centimeters.convertToInches()
    }

    private func displayLiveHeight(_ centimeters: Float) -> Double {
        let snappedHeight = HeightDisplay.snappedStoredHeight(
            centimeters,
            sitting: preferences.sittingPosition,
            standing: preferences.standingPosition
        )

        return HeightDisplay.roundedDisplayHeight(Double(displayHeight(snappedHeight)))
    }

    private func formatted(_ value: Double) -> String {
        let isWholeNumber = abs(value.rounded() - value) < 0.05
        return value.formatted(.number.precision(.fractionLength(isWholeNumber ? 0 : 1)))
    }
}

private struct DoubleTapStatusIndicator: View {
    let isConnected: Bool

    var body: some View {
        Image(systemName: isConnected ? "hand.tap.fill" : "hand.tap")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isConnected ? Color.accentColor : Color.secondary)
            .frame(width: 23, height: 23)
            .background((isConnected ? Color.accentColor : Color.secondary).opacity(0.10))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder((isConnected ? Color.accentColor : Color.secondary).opacity(0.18))
            }
            .help(isConnected ? "Handle double tap enabled" : "Handle double tap enabled after reconnect")
    }
}

private struct DeskSwitcherStrip: View {
    let desks: [DeskAppModel.DeskSummary]
    let select: (UUID) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(desks) { desk in
                Button {
                    select(desk.id)
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(desk.isActive ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 6, height: 6)
                        Text(desk.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(desk.isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.58))
                    .foregroundStyle(desk.isActive ? Color.accentColor : Color.secondary)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(desk.isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12))
                    }
                }
                .buttonStyle(.plain)
                .help(desk.isActive ? "Active desk" : "Make active")
            }
        }
    }
}

private struct FirstRunGuide: View {
    let isScanning: Bool
    let startDiscovery: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isScanning ? 0.16 : 0.11))
                        .frame(width: 38, height: 38)
                    Image(systemName: isScanning ? "dot.radiowaves.left.and.right" : "sparkle.magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isScanning ? "Looking for your desk" : "Set up your desk")
                        .font(.headline)
                    Text(isScanning ? "Keep the desk powered and nearby." : "Connect once, then IDASEN Desk remembers it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                FirstRunStep(title: "Power", systemImage: "powerplug", isActive: false)
                FirstRunStep(title: "Find", systemImage: "dot.radiowaves.left.and.right", isActive: isScanning)
                FirstRunStep(title: "Save", systemImage: "checkmark.seal", isActive: false)
            }

            HStack(spacing: 8) {
                Button {
                    startDiscovery()
                } label: {
                    Label(isScanning ? "Scanning" : "Find Desk", systemImage: isScanning ? "wave.3.right" : "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)

                Button {
                    openSettings()
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18))
        }
    }
}

private struct FirstRunStep: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background((isActive ? Color.accentColor : Color.secondary).opacity(isActive ? 0.13 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MovementChip: View {
    let direction: MovingDirection
    let movingToPosition: Position?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.13))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: title)
    }

    private var title: String {
        if let movingToPosition {
            switch movingToPosition {
            case .sit:
                return "Sitting"
            case .stand:
                return "Standing"
            case .custom:
                return "Moving"
            }
        }

        switch direction {
        case .up:
            return "Up"
        case .down:
            return "Down"
        case .none:
            return "Idle"
        }
    }

    private var icon: String {
        switch direction {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .none:
            return movingToPosition == nil ? "checkmark" : "arrow.up.and.down"
        }
    }

    private var color: Color {
        switch direction {
        case .up:
            return .green
        case .down:
            return .blue
        case .none:
            return movingToPosition == nil ? .secondary : .accentColor
        }
    }
}

private struct HeightHero: View {
    let height: Double?
    let unit: String
    let direction: MovingDirection
    let statusColor: Color
    let sittingHeight: Double
    let standingHeight: Double

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Live height")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HeightValueReadout(value: heightText, unit: unit, valueSize: 54, unitSize: 20)

                Text(verbatim: relativeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            PostureOrb(
                cue: postureCue,
                direction: direction,
                tint: statusColor
            )
            .frame(width: 108, height: 108)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(direction == .none ? 0.10 : 0.15),
                            Color(nsColor: .controlBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        }
        .shadow(color: Color.accentColor.opacity(direction == .none ? 0.07 : 0.12), radius: 10, y: 4)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: height)
        .animation(.spring(response: 0.30, dampingFraction: 0.72), value: direction)
    }

    private var heightText: String {
        guard let height else {
            return "--"
        }

        return height.formatted(.number.precision(.fractionLength(1)))
    }

    private var relativeText: String {
        guard let height else {
            return AppStrings.localized("Waiting for desk position")
        }

        let sitDelta = height - sittingHeight
        let standDelta = height - standingHeight

        if abs(sitDelta) <= 0.2 {
            return AppStrings.localized("Aligned with sitting preset")
        }

        if abs(standDelta) <= 0.2 {
            return AppStrings.localized("Aligned with standing preset")
        }

        let target = AppStrings.localized(abs(sitDelta) < abs(standDelta) ? "Sitting" : "Standing")
        let delta = abs(sitDelta) < abs(standDelta) ? sitDelta : standDelta
        let amount = abs(delta).formatted(.number.precision(.fractionLength(1)))
        return AppStrings.format(
            delta > 0 ? "Height above %@ %@ %@" : "Height below %@ %@ %@",
            amount,
            unit,
            target
        )
    }

    private var postureCue: PostureCue {
        guard let height else {
            return PostureCue(title: "Waiting", systemImage: "dot.radiowaves.left.and.right", color: .secondary)
        }

        if abs(height - sittingHeight) <= 0.2 {
            return PostureCue(title: "Sitting", systemImage: "chair", color: .blue)
        }

        if abs(height - standingHeight) <= 0.2 {
            return PostureCue(title: "Standing", systemImage: "figure.stand", color: .green)
        }

        switch direction {
        case .up:
            return PostureCue(title: "Rising", systemImage: "arrow.up", color: .green)
        case .down:
            return PostureCue(title: "Lowering", systemImage: "arrow.down", color: .blue)
        case .none:
            return PostureCue(title: "Between", systemImage: "arrow.up.and.down", color: statusColor)
        }
    }
}

private struct PostureCue {
    let title: String
    let systemImage: String
    let color: Color
}

private struct PostureOrb: View {
    let cue: PostureCue
    let direction: MovingDirection
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            cue.color.opacity(direction == .none ? 0.20 : 0.28),
                            Color(nsColor: .controlBackgroundColor).opacity(0.86)
                        ],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 82
                    )
                )

            Circle()
                .strokeBorder(cue.color.opacity(direction == .none ? 0.18 : 0.34), lineWidth: 1)

            Circle()
                .strokeBorder(tint.opacity(direction == .none ? 0.08 : 0.18), lineWidth: direction == .none ? 8 : 12)
                .scaleEffect(direction == .none ? 0.82 : 0.96)

            VStack(spacing: 7) {
                Image(systemName: cue.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(LocalizedStringKey(cue.title))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(cue.color)

            if direction != .none {
                DirectionSpark(direction: direction, tint: tint)
                    .offset(x: 28, y: -30)
            }
        }
        .shadow(color: cue.color.opacity(direction == .none ? 0.08 : 0.18), radius: 10, y: 4)
        .animation(.spring(response: 0.32, dampingFraction: 0.76), value: cue.title)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: direction)
    }
}

private struct DirectionSpark: View {
    let direction: MovingDirection
    let tint: Color

    var body: some View {
        VStack(spacing: -2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .black))
                    .opacity([0.36, 0.62, 1.0][index])
            }
        }
        .foregroundStyle(tint)
        .padding(7)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.74))
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1)
        }
    }

    private var symbol: String {
        switch direction {
        case .up:
            return "chevron.up"
        case .down:
            return "chevron.down"
        case .none:
            return "minus"
        }
    }
}

private struct TargetButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isActive: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: isActive ? "stop.fill" : systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(title))
                        .font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(isActive ? tint.opacity(0.13) : Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isActive ? tint.opacity(0.40) : Color.secondary.opacity(0.14))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14))
                }
                .help(title)
        }
        .buttonStyle(.plain)
    }
}

private struct JogButton: View {
    let systemImage: String
    let title: String
    let start: () -> Void
    let stop: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
            Text(systemImage == "arrow.up" ? "Raise" : "Lower")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(isPressed ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPressed ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.70))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isPressed ? Color.accentColor.opacity(0.42) : Color.secondary.opacity(0.14))
        }
        .shadow(color: isPressed ? Color.accentColor.opacity(0.20) : .clear, radius: 8, y: 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else {
                        return
                    }

                    isPressed = true
                    start()
                }
                .onEnded { _ in
                    guard isPressed else {
                        return
                    }

                    isPressed = false
                    stop()
                }
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
    }
}
