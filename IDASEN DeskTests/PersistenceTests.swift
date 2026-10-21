import XCTest
@testable import IDASENDesk

@MainActor
final class PersistenceTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    func testPreferenceChangesPersist() {
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.standingHeight = 112.5
        preferences.customPresets = [CustomPreset(name: "Focus", height: 104)]
        preferences.hotKeys[.toggle] = HotKey(keyCode: 126, modifiers: 0, display: "↑")

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.standingHeight, 112.5)
        XCTAssertEqual(reloaded.customPresets.map(\.name), ["Focus"])
        XCTAssertEqual(reloaded.hotKeys[.toggle]?.display, "↑")
    }

    func testVersionOneHistoryStillDecodes() throws {
        // Shape written by 1.x's HealthStatsStore.
        let legacy = """
        [{"day":782438400,"workSeconds":3600,"sittingSeconds":2400,"standingSeconds":1000,
          "transitionSeconds":200,"standTransitions":2,"sessions":1,"firstSeen":782460000,"lastSeen":782463600}]
        """
        let defaults = freshDefaults()
        defaults.set(Data(legacy.utf8), forKey: "healthStatsDays")

        let store = ActivityStore(defaults: defaults)

        XCTAssertEqual(store.days.count, 1)
        XCTAssertEqual(store.days.first?.standingSeconds, 1000)
        XCTAssertEqual(store.days.first?.standTransitions, 2)
    }

    func testRecentDaysFillsGaps() {
        let store = ActivityStore(defaults: freshDefaults())
        store.add(.standing, seconds: 600)
        store.recordStandUp()

        let week = store.recentDays(7)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.standingSeconds, 600)
        XCTAssertEqual(week.last?.standTransitions, 1)
        XCTAssertEqual(week.first?.trackedSeconds, 0)
    }
}
