import Foundation

/// Tracks one move-to-height request and decides when it is over.
///
/// The controller does the actual positioning (soft start, soft stop, millimetre
/// accuracy). This type only watches the position reports to tell arrival apart from
/// the desk stalling, someone grabbing the handle, or nothing happening at all.
struct TargetMove: Equatable {
    enum Outcome: Equatable {
        case moving
        case arrived
        /// Stopped away from the target: obstacle, column limit, or anti-collision.
        case stalled
        /// The desk moved away from the target, which means the handle was used.
        case interrupted
        case timedOut
    }

    /// Close enough to call it arrived once the desk is still (5 mm).
    static let arrivalTolerance = 50
    /// How far off the desk may be before reverse movement counts as an interruption (1 cm).
    static let interruptionMargin = 100
    /// How long the desk may take to start moving after the first command.
    static let startupGrace: TimeInterval = 2.5
    static let timeout: TimeInterval = 60

    let targetRaw: Int
    let startedAt: Date
    private(set) var hasMoved = false

    init(targetRaw: Int, startedAt: Date) {
        self.targetRaw = targetRaw
        self.startedAt = startedAt
    }

    func isArrived(at raw: Int) -> Bool {
        abs(targetRaw - raw) <= Self.arrivalTolerance
    }

    mutating func evaluate(_ report: DeskProtocol.PositionReport?, at time: Date) -> Outcome {
        let elapsed = time.timeIntervalSince(startedAt)

        guard elapsed <= Self.timeout else {
            return .timedOut
        }

        guard let report else {
            return elapsed > Self.startupGrace ? .stalled : .moving
        }

        let remaining = targetRaw - report.raw

        if report.speed != 0 {
            hasMoved = true

            let movingTowardTarget = (remaining > 0) == (report.speed > 0)
            if !movingTowardTarget, abs(remaining) > Self.interruptionMargin {
                return .interrupted
            }

            return .moving
        }

        if isArrived(at: report.raw) {
            return .arrived
        }

        if hasMoved || elapsed > Self.startupGrace {
            return .stalled
        }

        return .moving
    }
}
