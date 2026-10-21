import XCTest
@testable import IDASENDesk

final class PostureTrackerTests: XCTestCase {
    private var tracker = PostureTracker()
    private var clock = Date(timeIntervalSinceReferenceDate: 0)

    /// Records `count` samples ten seconds apart.
    @discardableResult
    private func run(_ posture: Posture?, present: Bool = true, samples count: Int) -> [PostureTracker.Event] {
        (0..<count).map { _ in
            clock.addTimeInterval(10)
            return tracker.record(posture: posture, isPresent: present, at: clock)
        }
    }

    func testClassifiesAroundTheMidpoint() {
        XCTAssertEqual(Posture.classify(height: 80, sittingHeight: 72, standingHeight: 110), .sitting)
        XCTAssertEqual(Posture.classify(height: 95, sittingHeight: 72, standingHeight: 110), .standing)
    }

    func testAccumulatesSittingTime() {
        run(.sitting, samples: 1)
        run(.sitting, samples: 6)
        XCTAssertEqual(tracker.posture, .sitting)
        XCTAssertEqual(tracker.streak, 60, accuracy: 0.1)
    }

    func testBriefStandDoesNotEndTheStreak() {
        run(.sitting, samples: 31)
        run(.standing, samples: 3)
        run(.sitting, samples: 1)
        XCTAssertEqual(tracker.posture, .sitting)
        XCTAssertEqual(tracker.streak, 310, accuracy: 0.1)
    }

    func testStandingForAMinuteSwitchesPosture() {
        run(.sitting, samples: 31)
        let events = run(.standing, samples: 6)
        XCTAssertEqual(events.last, .switched(from: .sitting, to: .standing))
        XCTAssertEqual(tracker.posture, .standing)
        XCTAssertEqual(tracker.streak, 60, accuracy: 0.1)
    }

    func testShortAbsencePausesButLongAbsenceIsABreak() {
        run(.sitting, samples: 31)
        run(.sitting, present: false, samples: 12)
        XCTAssertEqual(tracker.posture, .sitting)
        XCTAssertEqual(tracker.streak, 300, accuracy: 0.1)

        let events = run(.sitting, present: false, samples: 20)
        XCTAssertTrue(events.contains(.tookBreak))
        XCTAssertNil(tracker.posture)
    }

    func testSleepGapCountsAsBreak() {
        run(.sitting, samples: 31)
        clock.addTimeInterval(3600)
        XCTAssertEqual(tracker.record(posture: .sitting, isPresent: true, at: clock), .tookBreak)
    }
}
