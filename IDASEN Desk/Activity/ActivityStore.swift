import Foundation
import Observation

/// One day of posture totals. Field names match 1.x so saved history still decodes.
struct ActivityDay: Codable, Equatable, Identifiable {
    var day: Date
    var sittingSeconds: TimeInterval = 0
    var standingSeconds: TimeInterval = 0
    var standTransitions: Int = 0

    var id: Date {
        day
    }

    var trackedSeconds: TimeInterval {
        sittingSeconds + standingSeconds
    }

    var standingShare: Double {
        trackedSeconds > 0 ? standingSeconds / trackedSeconds : 0
    }
}

/// Local, on-device posture history.
@MainActor
@Observable
final class ActivityStore {
    private static let key = "healthStatsDays"
    private static let retentionDays = 400

    private(set) var days: [ActivityDay]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var calendar = Calendar.autoupdatingCurrent
    @ObservationIgnored private var lastSaved = Date.distantPast

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        days = (defaults.decoded([ActivityDay].self, forKey: Self.key) ?? []).sorted { $0.day < $1.day }
    }

    func add(_ posture: Posture, seconds: TimeInterval, at date: Date = Date()) {
        guard seconds > 0 else {
            return
        }

        update(dayOf: date) { day in
            switch posture {
            case .sitting:
                day.sittingSeconds += seconds
            case .standing:
                day.standingSeconds += seconds
            }
        }
    }

    func recordStandUp(at date: Date = Date()) {
        update(dayOf: date) { $0.standTransitions += 1 }
    }

    func day(containing date: Date) -> ActivityDay {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.day == start } ?? ActivityDay(day: start)
    }

    /// The last `count` days ending today, including empty ones.
    func recentDays(_ count: Int, endingAt date: Date = Date()) -> [ActivityDay] {
        let today = calendar.startOfDay(for: date)
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })

        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { byDay[$0] ?? ActivityDay(day: $0) }
        }
    }

    func reset() {
        days = []
        save()
    }

    func save() {
        defaults.setEncoded(days, forKey: Self.key)
        lastSaved = Date()
    }

    private func update(dayOf date: Date, _ change: (inout ActivityDay) -> Void) {
        let start = calendar.startOfDay(for: date)

        if let index = days.lastIndex(where: { $0.day == start }) {
            change(&days[index])
        } else {
            var day = ActivityDay(day: start)
            change(&day)
            days.append(day)
            days.sort { $0.day < $1.day }
            prune()
        }

        if Date().timeIntervalSince(lastSaved) > 60 {
            save()
        }
    }

    private func prune() {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: calendar.startOfDay(for: Date())) else {
            return
        }

        days.removeAll { $0.day < cutoff }
    }

    #if DEBUG
    func setPreviewDays(_ days: [ActivityDay]) {
        self.days = days
    }
    #endif
}
