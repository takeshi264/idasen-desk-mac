import CoreBluetooth
import Foundation
import os

/// One connected desk: GATT discovery, position notifications, and motion.
///
/// All CoreBluetooth callbacks arrive on the main queue (the central is created with
/// `queue: nil`), so the whole type is main-actor isolated.
@MainActor
final class DeskConnection: NSObject {
    enum Motion: Equatable {
        case idle
        case target(TargetMove)
        case jog(MovingDirection)
    }

    let peripheral: CBPeripheral

    var id: UUID {
        peripheral.identifier
    }

    private(set) var report: DeskProtocol.PositionReport?
    private(set) var motion: Motion = .idle

    /// Ready once the desk can be both read and driven.
    var isReady: Bool {
        controlCharacteristic != nil && report != nil
    }

    var direction: MovingDirection {
        MovingDirection(speed: report?.speed ?? 0)
    }

    var targetRaw: Int? {
        if case .target(let move) = motion {
            return move.targetRaw
        }
        return nil
    }

    /// Position, readiness or motion changed.
    var onChange: (() -> Void)?
    var onHandleDoubleTap: ((MovingDirection) -> Void)?
    var onMoveFinished: ((TargetMove.Outcome) -> Void)?

    private var controlCharacteristic: CBCharacteristic?
    private var positionCharacteristic: CBCharacteristic?
    private var referenceCharacteristic: CBCharacteristic?

    private let ticker = RepeatingTask()
    private var activity: NSObjectProtocol?

    private var gestureDetector = HandleGestureDetector()
    private var gesturesSuppressedUntil = Date.distantPast

    /// The controller keeps moving for about a second per command, so commands are
    /// repeated well inside that window to keep motion continuous.
    private static let commandInterval: Duration = .milliseconds(300)
    private static let maximumJogDuration: TimeInterval = 30
    private static let logger = Logger(subsystem: "com.takeshi264.idasen-desk-mac", category: "motion")

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    func discover() {
        peripheral.discoverServices(DeskProtocol.services)
    }

    // MARK: - Motion

    func move(toRaw rawTarget: Int) {
        let target = rawTarget.clamped(to: DeskProtocol.rawTravel)
        endMotion(sendStop: false)

        guard let control = controlCharacteristic, peripheral.state == .connected else {
            return
        }

        if let report, abs(report.raw - target) <= TargetMove.arrivalTolerance {
            onMoveFinished?(.arrived)
            return
        }

        beginActivity()
        gestureDetector.reset()
        motion = .target(TargetMove(targetRaw: target, startedAt: Date()))

        if referenceCharacteristic != nil {
            // The controller ignores reference input until it has been woken and stopped.
            write(DeskProtocol.Command.wakeUp, to: control)
            write(DeskProtocol.Command.stop, to: control)
        }

        sendTargetCommand()
        ticker.start(every: Self.commandInterval) { [weak self] in
            self?.tick()
        }
        onChange?()
    }

    func startJog(_ direction: MovingDirection) {
        guard direction != .none else {
            stop()
            return
        }

        endMotion(sendStop: false)

        guard controlCharacteristic != nil, peripheral.state == .connected else {
            return
        }

        beginActivity()
        gestureDetector.reset()
        motion = .jog(direction)
        let startedAt = Date()

        sendJogCommand(direction)
        ticker.start(every: Self.commandInterval) { [weak self] in
            guard let self else {
                return
            }

            // Safety net in case the release event never arrives.
            if Date().timeIntervalSince(startedAt) > Self.maximumJogDuration {
                self.stop()
            } else {
                self.sendJogCommand(direction)
            }
        }
        onChange?()
    }

    func stop() {
        endMotion(sendStop: true)
    }

    // MARK: - Private

    private func tick() {
        guard case .target(var move) = motion else {
            return
        }

        let outcome = move.evaluate(report, at: Date())
        motion = .target(move)

        if outcome == .moving {
            sendTargetCommand()
        } else {
            finishTargetMove(outcome)
        }
    }

    private func handle(_ newReport: DeskProtocol.PositionReport) {
        report = newReport

        switch motion {
        case .target(var move):
            let outcome = move.evaluate(newReport, at: Date())
            motion = .target(move)

            if outcome != .moving {
                finishTargetMove(outcome)
            } else if referenceCharacteristic == nil {
                stopEarlyIfNeeded(for: move, report: newReport)
            }

        case .jog:
            break

        case .idle:
            detectHandleGesture(direction: MovingDirection(speed: newReport.speed))
        }

        onChange?()
    }

    private func sendTargetCommand() {
        guard case .target(let move) = motion, let control = controlCharacteristic else {
            return
        }

        if let reference = referenceCharacteristic {
            write(DeskProtocol.encodeReference(raw: move.targetRaw), to: reference)
            return
        }

        // Fallback for controllers without reference input: plain up/down commands.
        guard let report else {
            return
        }

        write(move.targetRaw > report.raw ? DeskProtocol.Command.moveUp : DeskProtocol.Command.moveDown, to: control)
    }

    /// Without reference input the desk coasts after a stop, so stop a little early.
    private func stopEarlyIfNeeded(for move: TargetMove, report: DeskProtocol.PositionReport) {
        let remaining = move.targetRaw - report.raw
        let coastDistance = 60

        let overshooting = report.speed != 0 && (remaining > 0) != (report.speed > 0)
        if abs(remaining) <= coastDistance || overshooting {
            if let control = controlCharacteristic {
                write(DeskProtocol.Command.stop, to: control)
            }
            finishTargetMove(.arrived)
        }
    }

    private func sendJogCommand(_ direction: MovingDirection) {
        guard let control = controlCharacteristic else {
            return
        }

        write(direction == .up ? DeskProtocol.Command.moveUp : DeskProtocol.Command.moveDown, to: control)
    }

    private func finishTargetMove(_ outcome: TargetMove.Outcome) {
        Self.logger.info("Move finished: \(String(describing: outcome), privacy: .public)")
        endMotion(sendStop: outcome == .interrupted || outcome == .timedOut)
        onMoveFinished?(outcome)
    }

    private func endMotion(sendStop: Bool) {
        let wasMoving = motion != .idle
        ticker.stop()
        motion = .idle

        if sendStop, let control = controlCharacteristic, peripheral.state == .connected {
            write(DeskProtocol.Command.stop, to: control)
        }

        if wasMoving {
            // Let the desk settle before handle taps are interpreted again.
            gesturesSuppressedUntil = Date().addingTimeInterval(1.2)
            gestureDetector.reset()
            endActivity()
            onChange?()
        }
    }

    private func detectHandleGesture(direction: MovingDirection) {
        let now = Date()
        guard now >= gesturesSuppressedUntil else {
            return
        }

        if let tapDirection = gestureDetector.record(direction, at: now) {
            onHandleDoubleTap?(tapDirection)
        }
    }

    private func write(_ data: Data, to characteristic: CBCharacteristic) {
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    /// Keeps App Nap from stretching the command loop while the desk is moving.
    private func beginActivity() {
        guard activity == nil else {
            return
        }

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Moving the desk"
        )
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }

    fileprivate func reset() {
        endMotion(sendStop: false)
        controlCharacteristic = nil
        positionCharacteristic = nil
        referenceCharacteristic = nil
    }
}

// MARK: - CBPeripheralDelegate

extension DeskConnection: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, let services = peripheral.services else {
                return
            }

            for service in services {
                switch service.uuid {
                case DeskProtocol.controlService:
                    peripheral.discoverCharacteristics([DeskProtocol.controlCharacteristic], for: service)
                case DeskProtocol.positionService:
                    peripheral.discoverCharacteristics([DeskProtocol.positionCharacteristic], for: service)
                case DeskProtocol.referenceInputService:
                    peripheral.discoverCharacteristics([DeskProtocol.referenceInputCharacteristic], for: service)
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil else {
                return
            }

            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid {
                case DeskProtocol.controlCharacteristic:
                    controlCharacteristic = characteristic
                case DeskProtocol.positionCharacteristic:
                    positionCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                case DeskProtocol.referenceInputCharacteristic:
                    referenceCharacteristic = characteristic
                default:
                    break
                }
            }

            onChange?()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil,
                  characteristic.uuid == DeskProtocol.positionCharacteristic,
                  let value = characteristic.value,
                  let report = DeskProtocol.decodePosition(value) else {
                return
            }

            handle(report)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        MainActor.assumeIsolated {
            reset()
            discover()
            onChange?()
        }
    }
}
