import CoreBluetooth
import Foundation

final class DeskPeripheral: NSObject {

    static let deskPositionServiceUUID = CBUUID(string: "99FA0020-338A-1024-8A49-009C0215F78A")
    static let deskPositionCharacteristicUUID = CBUUID(string: "99FA0021-338A-1024-8A49-009C0215F78A")

    static let deskControlServiceUUID = CBUUID(string: "99FA0001-338A-1024-8A49-009C0215F78A")
    static let deskControlCharacteristicUUID = CBUUID(string: "99FA0002-338A-1024-8A49-009C0215F78A")

    static let heightPositionOffset: Float = 61.5
    private static let positionUpdateThreshold: Float = 0.02

    let peripheral: CBPeripheral

    var positionService: CBService?
    var positionCharacteristic: CBCharacteristic?

    var controlService: CBService?
    var controlCharacteristic: CBCharacteristic?

    var speed: Float = 0

    var hasLoadedPositionCharacteristicValues = false

    var onPositionChange: (Float) -> Void = { _ in }

    var position: Float? {
        didSet {
            if let oldValue = oldValue,
               let position = position,
               abs(oldValue - position) < Self.positionUpdateThreshold {
                return
            }

            if let position = position, hasLoadedPositionCharacteristicValues {
                onPositionChange(position)
            }

        }
    }

    private let switchControlDoubleTapDetector = SwitchControlDoubleTapDetector()
    private var movementDirection: MovingDirection = .none
    var onMovementDirectionChange: (MovingDirection) -> Void = { _ in }
    var onDoubleTapDetected: ((_ direction: MovingDirection) -> Void)?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral

        super.init()

        peripheral.delegate = self
        peripheral.discoverServices([
            Self.deskPositionServiceUUID,
            Self.deskControlServiceUUID
        ])
    }

    deinit {
        if peripheral.delegate === self {
            peripheral.delegate = nil
        }
    }
}

extension DeskPeripheral: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, peripheral == self.peripheral, let services = peripheral.services else {
            return
        }

        for service in services {
            if service.uuid == DeskPeripheral.deskPositionServiceUUID {
                positionService = service
                peripheral.discoverCharacteristics([DeskPeripheral.deskPositionCharacteristicUUID], for: service)
            } else if service.uuid == DeskPeripheral.deskControlServiceUUID {
                controlService = service
                peripheral.discoverCharacteristics([DeskPeripheral.deskControlCharacteristicUUID], for: service)
            } else {
                continue
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        guard error == nil, peripheral == self.peripheral, let characteristics = service.characteristics else {
            return
        }

        for characteristic in characteristics {
            if characteristic.uuid == DeskPeripheral.deskPositionCharacteristicUUID {
                positionCharacteristic = characteristic

                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == DeskPeripheral.deskControlCharacteristicUUID {
                controlCharacteristic = characteristic
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {

        if error == nil, characteristic == positionCharacteristic, let value = characteristic.value {
            guard value.count >= 4 else {
                return
            }

            hasLoadedPositionCharacteristicValues = true

            let positionValue = UInt16(value[0]) | (UInt16(value[1]) << 8)
            let speedValue = Int16(bitPattern: UInt16(value[2]) | (UInt16(value[3]) << 8))

            speed = Float(speedValue)
            detectSwitchAction(speed: speed)
            position = Float(positionValue) / 100 + DeskPeripheral.heightPositionOffset
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral == self.peripheral else {
            return
        }

        if invalidatedServices.contains(where: { $0.uuid == DeskPeripheral.deskPositionServiceUUID }) {
            positionService = nil
            positionCharacteristic = nil
            hasLoadedPositionCharacteristicValues = false
        }

        if invalidatedServices.contains(where: { $0.uuid == DeskPeripheral.deskControlServiceUUID }) {
            controlService = nil
            controlCharacteristic = nil
        }

        peripheral.discoverServices([
            Self.deskPositionServiceUUID,
            Self.deskControlServiceUUID
        ])
    }

    private func detectSwitchAction(speed: Float) {
        let direction: MovingDirection = if speed < 0 {
            .down
        } else if speed > 0 {
            .up
        } else {
            .none
        }

        if direction != movementDirection {
            movementDirection = direction
            onMovementDirectionChange(direction)
        }

        if let doubleTapDirection = switchControlDoubleTapDetector.record(direction: direction) {
            onDoubleTapDetected?(doubleTapDirection)
        }
    }

    func suppressSwitchActionDetection(for duration: TimeInterval = 1.5) {
        switchControlDoubleTapDetector.suppress(for: duration)
    }

    func resetSwitchActionDetection() {
        switchControlDoubleTapDetector.reset()
    }
}

final class SwitchControlDoubleTapDetector {
    private enum State {
        case idle
        case pressed(direction: MovingDirection, time: Date)
        case released(direction: MovingDirection, firstTapTime: Date, releaseTime: Date)
    }

    private let maximumInterval: TimeInterval
    private let maximumReleaseInterval: TimeInterval
    private let cooldownInterval: TimeInterval
    private var state: State = .idle
    private var lastDirection: MovingDirection = .none
    private var suppressedUntil: Date?
    private var cooldownUntil: Date?
    private var needsNeutralAfterSuppression = false
    private var neutralAfterSuppressionDeadline: Date?
    private let lock = NSLock()

    init(
        maximumInterval: TimeInterval = 1.8,
        maximumReleaseInterval: TimeInterval = 1.35,
        cooldownInterval: TimeInterval = 0.25
    ) {
        self.maximumInterval = maximumInterval
        self.maximumReleaseInterval = maximumReleaseInterval
        self.cooldownInterval = cooldownInterval
    }

    func record(direction: MovingDirection, at time: Date = Date()) -> MovingDirection? {
        lock.lock()
        defer { lock.unlock() }

        if let suppressedUntil = suppressedUntil {
            guard time >= suppressedUntil else {
                state = .idle
                needsNeutralAfterSuppression = true
                neutralAfterSuppressionDeadline = suppressedUntil.addingTimeInterval(0.45)
                return nil
            }

            self.suppressedUntil = nil
            state = .idle
            lastDirection = .none
        }

        if needsNeutralAfterSuppression {
            let deadline = neutralAfterSuppressionDeadline ?? time
            if direction == .none || time >= deadline {
                needsNeutralAfterSuppression = false
                neutralAfterSuppressionDeadline = nil
            } else {
                state = .idle
                return nil
            }
        }

        if let cooldownUntil = cooldownUntil {
            guard time >= cooldownUntil else {
                return nil
            }

            self.cooldownUntil = nil
            lastDirection = .none
        }

        guard direction != lastDirection else {
            return nil
        }

        lastDirection = direction

        expireStateIfNeeded(at: time)

        if direction == .none {
            if case .pressed(let pressedDirection, let pressedTime) = state {
                state = .released(
                    direction: pressedDirection,
                    firstTapTime: pressedTime,
                    releaseTime: time
                )
            }

            return nil
        }

        switch state {
        case .idle:
            state = .pressed(direction: direction, time: time)

        case .pressed:
            state = .pressed(direction: direction, time: time)

        case .released(let firstDirection, let firstTapTime, let releaseTime):
            guard direction == firstDirection,
                  time.timeIntervalSince(firstTapTime) <= maximumInterval,
                  time.timeIntervalSince(releaseTime) <= maximumReleaseInterval else {
                state = .pressed(direction: direction, time: time)
                return nil
            }

            state = .idle
            cooldownUntil = time.addingTimeInterval(cooldownInterval)
            return direction
        }

        return nil
    }

    func suppress(for duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        state = .idle
        lastDirection = .none
        cooldownUntil = nil
        needsNeutralAfterSuppression = true

        let newSuppressionEnd = Date().addingTimeInterval(duration)
        if let currentSuppressionEnd = suppressedUntil, currentSuppressionEnd > newSuppressionEnd {
            return
        }

        suppressedUntil = newSuppressionEnd
        neutralAfterSuppressionDeadline = newSuppressionEnd.addingTimeInterval(0.45)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        state = .idle
        lastDirection = .none
        suppressedUntil = nil
        cooldownUntil = nil
        needsNeutralAfterSuppression = false
        neutralAfterSuppressionDeadline = nil
    }

    private func expireStateIfNeeded(at time: Date) {
        switch state {
        case .idle:
            break
        case .pressed(_, let pressedTime):
            if time.timeIntervalSince(pressedTime) > maximumInterval {
                state = .idle
            }
        case .released(_, let firstTapTime, let releaseTime):
            if time.timeIntervalSince(firstTapTime) > maximumInterval ||
               time.timeIntervalSince(releaseTime) > maximumReleaseInterval {
                state = .idle
            }
        }
    }
}
