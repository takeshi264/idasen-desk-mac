import Foundation

enum Posture: String, Codable {
    case sitting
    case standing

    /// Anything above the midpoint between the two presets counts as standing.
    static func classify(height: Double, sittingHeight: Double, standingHeight: Double) -> Posture {
        let midpoint = (min(sittingHeight, standingHeight) + max(sittingHeight, standingHeight)) / 2
        return height >= midpoint ? .standing : .sitting
    }
}

/// Measures how long someone has been continuously sitting or standing.
///
/// Time only counts while the person is at the Mac. Stepping away for a few minutes
/// pauses the clock; staying away long enough counts as a real break and resets it.
/// A posture change has to hold for a minute before it ends the current streak, so
/// popping up for a few seconds does not reset an hour of sitting.
struct PostureTracker: Equatable {
    static let breakDuration: TimeInterval = 5 * 60
    static let switchConfirmation: TimeInterval = 60
    /// Longer gaps between samples (sleep, App Nap) are not credited.
    static let maximumSampleGap: TimeInterval = 120

    enum Event: Equatable {
        case none
        /// A new posture was confirmed; `from` is nil after a break or at start.
        case switched(from: Posture?, to: Posture)
        case tookBreak
    }

    private(set) var posture: Posture?
    /// Continuous time in `posture`, at the Mac.
    private(set) var streak: TimeInterval = 0
    /// Increments whenever a streak ends, so callers can tell runs apart.
    private(set) var runID = 0

    private var pendingPosture: Posture?
    private var pendingDuration: TimeInterval = 0
    private var awayDuration: TimeInterval = 0
    private var lastSample: Date?

    /// `posture` is nil when the desk height is unknown (for example, disconnected).
    @discardableResult
    mutating func record(posture observed: Posture?, isPresent: Bool, at time: Date) -> Event {
        let elapsed = lastSample.map { time.timeIntervalSince($0) } ?? 0
        lastSample = time

        guard elapsed >= 0, elapsed <= Self.maximumSampleGap else {
            return none(orBreakAfter: Self.breakDuration)
        }

        guard isPresent, let observed else {
            return none(orBreakAfter: elapsed)
        }

        awayDuration = 0

        guard let current = posture else {
            posture = observed
            streak = 0
            runID += 1
            return .switched(from: nil, to: observed)
        }

        if observed == current {
            pendingPosture = nil
            pendingDuration = 0
            streak += elapsed
            return .none
        }

        if pendingPosture == observed {
            pendingDuration += elapsed
        } else {
            pendingPosture = observed
            pendingDuration = elapsed
        }

        guard pendingDuration >= Self.switchConfirmation else {
            return .none
        }

        posture = observed
        streak = pendingDuration
        pendingPosture = nil
        pendingDuration = 0
        runID += 1
        return .switched(from: current, to: observed)
    }

    private mutating func none(orBreakAfter away: TimeInterval) -> Event {
        awayDuration += away

        guard awayDuration >= Self.breakDuration, posture != nil else {
            return .none
        }

        posture = nil
        streak = 0
        pendingPosture = nil
        pendingDuration = 0
        runID += 1
        return .tookBreak
    }
}
