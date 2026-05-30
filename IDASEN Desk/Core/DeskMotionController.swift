import AppKit
import CoreBluetooth

enum MovingDirection: Equatable {
    case up, down, none
}

enum Position: Equatable {
    case sit, stand, custom(height: Float)
}

final class DeskMotionController: NSObject {
    private enum Command {
        static let moveUp = Data([0x47, 0x00])
        static let moveDown = Data([0x46, 0x00])
        static let stop = Data([0xFF, 0x00])
    }

    var onCurrentMovingDirectionChange: (MovingDirection) -> Void = { _ in }
    var currentMovingDirection: MovingDirection = .none {
        didSet {
            guard oldValue != currentMovingDirection else {
                return
            }

            onCurrentMovingDirectionChange(currentMovingDirection)
        }
    }

    var onDoubleTapDetected: ((_ direction: MovingDirection) -> Void)? {
        didSet {
            desk.onDoubleTapDetected = onDoubleTapDetected
        }
    }

    var movingToPosition: Position? {
        didSet {
            guard oldValue != movingToPosition else {
                return
            }

            onMovingToPositionChange(movingToPosition)
            moveIfNeeded()
        }
    }
    var onMovingToPositionChange: (Position?) -> Void = { _ in }

    let desk: DeskPeripheral

    let autoStand: AutoStand

    private let distanceOffset: Float = 0.5
    private let minDurationIncrements: TimeInterval = 0.5
    private let appMovementSwitchDetectionSuppression: TimeInterval = 0.65
    private let switchGestureSettleDelay: TimeInterval = 0.28
    private let switchGestureExternalStopGrace: TimeInterval = 1.1
    private let switchGestureResumeDelay: TimeInterval = 0.18
    private var lastMoveTime: Date
    private var hasObservedMovementDuringTargetMove = false
    private var isActiveController = false
    private var switchGestureMoveWorkItem: DispatchWorkItem?
    private var targetMoveResumeWorkItem: DispatchWorkItem?
    private var ignoreExternalStopUntil: Date?

    private let minMovementIncrements: Float = 0.5
    static var shared: DeskMotionController?

    private var positionChangeCallbacks = [(Float) -> Void]()

    init(desk: DeskPeripheral) {
        self.desk = desk
        self.lastMoveTime = Date().addingTimeInterval(-minDurationIncrements)
        self.autoStand = AutoStand()
        super.init()

        desk.onPositionChange = { [weak self] position in
            guard let self = self else {
                return
            }

            self.moveIfNeeded()
            self.positionChangeCallbacks.forEach { $0(position) }
        }

        desk.onMovementDirectionChange = { [weak self] direction in
            self?.handleDeskMovementDirectionChange(direction)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onWakeNote(note:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc func onWakeNote(note: NSNotification) {
        guard isActiveController else {
            return
        }

        let preferences = Preferences.shared
        if let preferredID = preferences.activeDeskID ?? preferences.knownDesks.first?.id {
            BluetoothManager.shared.connectKnownDesks(ids: [preferredID])
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        resignActive()
    }

    func becomeActive() {
        guard !isActiveController else {
            return
        }

        isActiveController = true
        DeskMotionController.shared = self
        autoStand.update()
    }

    func resignActive() {
        guard isActiveController else {
            return
        }

        isActiveController = false
        autoStand.unschedule()

        if DeskMotionController.shared === self {
            DeskMotionController.shared = nil
        }
    }

    func onPositionChange(_ callback: @escaping (Float) -> Void) {
        positionChangeCallbacks.append(callback)
    }


    func moveUp() {
        guard desk.peripheral.state == .connected,
              let characteristic = desk.controlCharacteristic else {
            return
        }

        desk.suppressSwitchActionDetection(for: appMovementSwitchDetectionSuppression)
        desk.peripheral.writeValue(Command.moveUp, for: characteristic, type: .withResponse)
        lastMoveTime = Date()
        currentMovingDirection = .up
    }

    func moveDown() {
        guard desk.peripheral.state == .connected,
              let characteristic = desk.controlCharacteristic else {
            return
        }

        desk.suppressSwitchActionDetection(for: appMovementSwitchDetectionSuppression)
        desk.peripheral.writeValue(Command.moveDown, for: characteristic, type: .withResponse)
        lastMoveTime = Date()
        currentMovingDirection = .down
    }

    func stopMoving() {
        switchGestureMoveWorkItem?.cancel()
        switchGestureMoveWorkItem = nil
        targetMoveResumeWorkItem?.cancel()
        targetMoveResumeWorkItem = nil
        ignoreExternalStopUntil = nil

        defer {
            currentMovingDirection = .none
            movingToPosition = nil
            previousPosition = nil
            hasObservedMovementDuringTargetMove = false
        }

        guard desk.peripheral.state == .connected,
              let characteristic = desk.controlCharacteristic else {
            desk.resetSwitchActionDetection()
            return
        }

        desk.suppressSwitchActionDetection(for: 0.35)
        desk.peripheral.writeValue(Command.stop, for: characteristic, type: .withResponse)
    }

    func moveToPosition(_ position: Position) {
        startTargetMove(position, source: .app)
    }

    func moveToPositionAfterSwitchGesture(_ position: Position) {
        stopMoving()
        desk.suppressSwitchActionDetection(for: switchGestureSettleDelay + switchGestureExternalStopGrace)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.switchGestureMoveWorkItem = nil
            self.startTargetMove(position, source: .switchGesture)
        }

        switchGestureMoveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + switchGestureSettleDelay, execute: workItem)
    }

    private enum TargetMoveSource {
        case app
        case switchGesture
    }

    private func startTargetMove(_ position: Position, source: TargetMoveSource) {
        guard !isAtTarget(position) else {
            clearTargetMove()
            return
        }

        switch source {
        case .app:
            ignoreExternalStopUntil = nil
            desk.resetSwitchActionDetection()
        case .switchGesture:
            ignoreExternalStopUntil = Date().addingTimeInterval(switchGestureExternalStopGrace)
        }

        previousPosition = nil
        hasObservedMovementDuringTargetMove = desk.speed != 0
        movingToPosition = position
    }

    func moveToHeight(_ height: Float) {
        moveToPosition(.custom(height: height.clamped(to: 60...130)))
    }

    func jog(_ direction: MovingDirection, duration: TimeInterval = 0.35) {
        switch direction {
        case .up:
            moveUp()
        case .down:
            moveDown()
        case .none:
            stopMoving()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self,
                  self.currentMovingDirection == direction,
                  self.movingToPosition == nil else {
                return
            }

            self.stopMoving()
        }
    }


    private var previousPosition: Float?

    private func handleDeskMovementDirectionChange(_ direction: MovingDirection) {
        if direction != .none {
            if movingToPosition != nil {
                hasObservedMovementDuringTargetMove = true
            }

            currentMovingDirection = direction
            return
        }

        guard let targetPosition = movingToPosition,
              hasObservedMovementDuringTargetMove || currentMovingDirection != .none else {
            currentMovingDirection = .none
            return
        }

        if isAtTarget(targetPosition) {
            stopMoving()
        } else if shouldIgnoreExternalStopFromSwitchGesture {
            scheduleTargetMoveResume()
        } else {
            cancelTargetMoveAfterExternalStop()
        }
    }

    private var shouldIgnoreExternalStopFromSwitchGesture: Bool {
        guard let ignoreExternalStopUntil else {
            return false
        }

        guard Date() <= ignoreExternalStopUntil else {
            self.ignoreExternalStopUntil = nil
            return false
        }

        return true
    }

    private func scheduleTargetMoveResume() {
        targetMoveResumeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let targetPosition = self.movingToPosition else {
                return
            }

            self.targetMoveResumeWorkItem = nil
            self.moveTowardTarget(targetPosition)
        }

        targetMoveResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + switchGestureResumeDelay, execute: workItem)
    }

    private func moveTowardTarget(_ targetPosition: Position) {
        guard let position = desk.position else {
            return
        }

        if isAtTarget(targetPosition) {
            clearTargetMove()
            return
        }

        previousPosition = position
        hasObservedMovementDuringTargetMove = true

        if Preferences.shared.height(for: targetPosition) > position {
            moveUp()
        } else {
            moveDown()
        }
    }

    private func cancelTargetMoveAfterExternalStop() {
        desk.resetSwitchActionDetection()
        clearTargetMove()
    }

    private func isAtTarget(_ targetPosition: Position) -> Bool {
        guard let position = desk.position else {
            return false
        }

        return abs(Preferences.shared.height(for: targetPosition) - position) <= distanceOffset
    }

    private func moveIfNeeded() {

        guard let toPosition = movingToPosition, var position = desk.position else {
            return
        }

        let speed = desk.speed

        let timeSinceLastMove = lastMoveTime.distance(to: Date())
        let distanceSincePreviousPosition = abs((previousPosition ?? position + minMovementIncrements) - position)


        let positionToMoveTo = Preferences.shared.height(for: toPosition)

        if abs(positionToMoveTo - position) <= distanceOffset {
            if speed == 0 {
                clearTargetMove()
            } else {
                stopMoving()
            }

            return
        }


        if positionToMoveTo > position {

            if currentMovingDirection == .up {
                position += distanceOffset
            }

            if position < positionToMoveTo && speed >= 0 {
                if timeSinceLastMove > minDurationIncrements && distanceSincePreviousPosition >= minMovementIncrements {
                    previousPosition = position
                    moveUp()
                }

            } else {
                stopMoving()
            }
        } else if positionToMoveTo < position {

            if currentMovingDirection == .down {
                position -= distanceOffset
            }

            if position > positionToMoveTo && speed <= 0 {
                if timeSinceLastMove > minDurationIncrements && distanceSincePreviousPosition >= minMovementIncrements {
                    previousPosition = position
                    moveDown()
                }
            } else {
                stopMoving()
            }
        }


    }

    private func clearTargetMove() {
        switchGestureMoveWorkItem?.cancel()
        switchGestureMoveWorkItem = nil
        targetMoveResumeWorkItem?.cancel()
        targetMoveResumeWorkItem = nil
        ignoreExternalStopUntil = nil
        desk.resetSwitchActionDetection()
        movingToPosition = nil
        previousPosition = nil
        hasObservedMovementDuringTargetMove = false
        currentMovingDirection = .none
    }
}
