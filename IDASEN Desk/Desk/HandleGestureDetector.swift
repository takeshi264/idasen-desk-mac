import Foundation

/// Recognises two short taps on the desk's physical handle in the same direction.
///
/// The desk only reports movement, not button presses, so a "tap" is a short burst of
/// movement: speed leaves zero and returns to zero within `maximumTapDuration`. The
/// gesture fires on the second release, when the desk is already still, so the app's
/// follow-up move never fights the person's hand on the switch.
struct HandleGestureDetector {
    var maximumTapDuration: TimeInterval = 1.5
    var maximumGapBetweenTaps: TimeInterval = 1.2

    private struct Press {
        let direction: MovingDirection
        let startedAt: Date
        let isSecondTap: Bool
    }

    private struct Tap {
        let direction: MovingDirection
        let releasedAt: Date
    }

    private var lastDirection: MovingDirection = .none
    private var press: Press?
    private var lastTap: Tap?

    /// Feeds the latest movement direction; returns a direction when a double tap completes.
    mutating func record(_ direction: MovingDirection, at time: Date) -> MovingDirection? {
        guard direction != lastDirection else {
            return nil
        }

        // A direct reversal is a release followed by a new press.
        if lastDirection != .none, direction != .none {
            _ = record(.none, at: time)
        }

        lastDirection = direction

        if direction != .none {
            let continuesTap = lastTap.map {
                $0.direction == direction && time.timeIntervalSince($0.releasedAt) <= maximumGapBetweenTaps
            } ?? false

            press = Press(direction: direction, startedAt: time, isSecondTap: continuesTap)
            return nil
        }

        guard let press else {
            return nil
        }

        self.press = nil

        guard time.timeIntervalSince(press.startedAt) <= maximumTapDuration else {
            // A long hold is a deliberate manual adjustment, not a tap.
            lastTap = nil
            return nil
        }

        if press.isSecondTap {
            lastTap = nil
            return press.direction
        }

        lastTap = Tap(direction: press.direction, releasedAt: time)
        return nil
    }

    mutating func reset() {
        lastDirection = .none
        press = nil
        lastTap = nil
    }
}
