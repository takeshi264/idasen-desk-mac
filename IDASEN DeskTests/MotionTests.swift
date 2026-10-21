import XCTest
@testable import IDASENDesk

final class TargetMoveTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func report(_ raw: Int, _ speed: Int) -> DeskProtocol.PositionReport {
        DeskProtocol.PositionReport(raw: raw, speed: speed)
    }

    func testWaitsForTheDeskToStart() {
        var move = TargetMove(targetRaw: 4800, startedAt: start)
        XCTAssertEqual(move.evaluate(report(1000, 0), at: start.addingTimeInterval(0.5)), .moving)
    }

    func testArrivesWhenStillNearTarget() {
        var move = TargetMove(targetRaw: 4800, startedAt: start)
        XCTAssertEqual(move.evaluate(report(3000, 300), at: start.addingTimeInterval(2)), .moving)
        XCTAssertEqual(move.evaluate(report(4797, 0), at: start.addingTimeInterval(9)), .arrived)
    }

    func testStallsWhenStoppingShort() {
        var move = TargetMove(targetRaw: 4800, startedAt: start)
        _ = move.evaluate(report(3000, 300), at: start.addingTimeInterval(2))
        XCTAssertEqual(move.evaluate(report(3500, 0), at: start.addingTimeInterval(4)), .stalled)
    }

    func testStallsWhenNothingHappens() {
        var move = TargetMove(targetRaw: 4800, startedAt: start)
        XCTAssertEqual(move.evaluate(report(1000, 0), at: start.addingTimeInterval(3)), .stalled)
    }

    func testMovingAwayFromTargetIsAnInterruption() {
        var move = TargetMove(targetRaw: 4800, startedAt: start)
        _ = move.evaluate(report(3000, 300), at: start.addingTimeInterval(2))
        XCTAssertEqual(move.evaluate(report(2950, -200), at: start.addingTimeInterval(3)), .interrupted)
    }

    func testTimesOut() {
        var move = TargetMove(targetRaw: 4800, startedAt: start)
        XCTAssertEqual(move.evaluate(report(3000, 300), at: start.addingTimeInterval(61)), .timedOut)
    }
}

final class HandleGestureDetectorTests: XCTestCase {
    private var detector = HandleGestureDetector()
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func feed(_ direction: MovingDirection, _ seconds: TimeInterval) -> MovingDirection? {
        detector.record(direction, at: start.addingTimeInterval(seconds))
    }

    func testTwoQuickTapsUpFireOnSecondRelease() {
        XCTAssertNil(feed(.up, 0))
        XCTAssertNil(feed(.none, 0.4))
        XCTAssertNil(feed(.up, 0.9))
        XCTAssertEqual(feed(.none, 1.3), .up)
    }

    func testTapsInDifferentDirectionsDoNotFire() {
        XCTAssertNil(feed(.up, 0))
        XCTAssertNil(feed(.none, 0.4))
        XCTAssertNil(feed(.down, 0.9))
        XCTAssertNil(feed(.none, 1.3))
    }

    func testSlowTapsDoNotFire() {
        XCTAssertNil(feed(.down, 0))
        XCTAssertNil(feed(.none, 0.4))
        XCTAssertNil(feed(.down, 2.5))
        XCTAssertNil(feed(.none, 2.9))
    }

    func testLongHoldIsNotATap() {
        XCTAssertNil(feed(.up, 0))
        XCTAssertNil(feed(.none, 3))
        XCTAssertNil(feed(.up, 3.5))
        XCTAssertNil(feed(.none, 3.9))
    }

    func testThirdTapStartsOver() {
        XCTAssertNil(feed(.up, 0))
        XCTAssertNil(feed(.none, 0.3))
        XCTAssertNil(feed(.up, 0.7))
        XCTAssertEqual(feed(.none, 1.0), .up)
        XCTAssertNil(feed(.up, 1.4))
        XCTAssertNil(feed(.none, 1.7))
    }
}
