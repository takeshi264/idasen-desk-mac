import AppKit
import Foundation

enum HealthStatsPeriod: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .week:
            return AppStrings.localized("This Week")
        case .month:
            return AppStrings.localized("This Month")
        }
    }

    var shortTitle: String {
        switch self {
        case .week:
            return AppStrings.localized("Week")
        case .month:
            return AppStrings.localized("Month")
        }
    }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        let rawInterval: DateInterval

        switch self {
        case .week:
            rawInterval = calendar.dateInterval(of: .weekOfYear, for: date) ?? fallbackInterval(days: 7, endingAt: date, calendar: calendar)
        case .month:
            rawInterval = calendar.dateInterval(of: .month, for: date) ?? fallbackInterval(days: 30, endingAt: date, calendar: calendar)
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? rawInterval.end
        return DateInterval(start: rawInterval.start, end: min(rawInterval.end, tomorrow))
    }

    private func fallbackInterval(days: Int, endingAt date: Date, calendar: Calendar) -> DateInterval {
        let end = calendar.startOfDay(for: date).addingTimeInterval(24 * 60 * 60)
        let start = calendar.date(byAdding: .day, value: -days + 1, to: end) ?? end
        return DateInterval(start: start, end: end)
    }
}

enum HealthPosture: String, Codable {
    case sitting
    case standing
    case transition

    static func classify(height: Float?, sittingHeight: Float, standingHeight: Float) -> HealthPosture {
        guard let height else {
            return .transition
        }

        let lower = min(sittingHeight, standingHeight)
        let upper = max(sittingHeight, standingHeight)
        let span = max(upper - lower, 1)
        let sittingThreshold = lower + span * 0.38
        let standingThreshold = lower + span * 0.62

        if height <= sittingThreshold {
            return .sitting
        }

        if height >= standingThreshold {
            return .standing
        }

        return .transition
    }
}

struct HealthStatsDay: Codable, Equatable, Identifiable {
    var day: Date
    var workSeconds: TimeInterval = 0
    var sittingSeconds: TimeInterval = 0
    var standingSeconds: TimeInterval = 0
    var transitionSeconds: TimeInterval = 0
    var standTransitions: Int = 0
    var sessions: Int = 0
    var firstSeen: Date?
    var lastSeen: Date?

    var id: Date {
        day
    }

    var hasActivity: Bool {
        workSeconds > 0 || sessions > 0
    }
}

struct HealthStatsSummary: Equatable {
    let period: HealthStatsPeriod
    let startDate: Date
    let endDate: Date
    let days: [HealthStatsDay]

    var workSeconds: TimeInterval {
        days.reduce(0) { $0 + $1.workSeconds }
    }

    var sittingSeconds: TimeInterval {
        days.reduce(0) { $0 + $1.sittingSeconds }
    }

    var standingSeconds: TimeInterval {
        days.reduce(0) { $0 + $1.standingSeconds }
    }

    var transitionSeconds: TimeInterval {
        days.reduce(0) { $0 + $1.transitionSeconds }
    }

    var standTransitions: Int {
        days.reduce(0) { $0 + $1.standTransitions }
    }

    var sessions: Int {
        days.reduce(0) { $0 + $1.sessions }
    }

    var activeDays: Int {
        days.filter(\.hasActivity).count
    }

    var standingRatio: Double {
        guard workSeconds > 0 else {
            return 0
        }

        return standingSeconds / workSeconds
    }

    var sittingRatio: Double {
        guard workSeconds > 0 else {
            return 0
        }

        return sittingSeconds / workSeconds
    }

    var averageWorkdaySeconds: TimeInterval {
        guard activeDays > 0 else {
            return 0
        }

        return workSeconds / Double(activeDays)
    }

    var bestStandingDay: HealthStatsDay? {
        days.max { first, second in
            first.standingSeconds < second.standingSeconds
        }
    }

    var dateRangeText: String {
        let style = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .locale(AppStrings.locale)
        let start = startDate.formatted(style)
        let end = endDate.addingTimeInterval(-1).formatted(style)
        return AppStrings.format("Date range %@", "\(start) - \(end)")
    }

    var insightText: String {
        guard workSeconds > 0 else {
            return AppStrings.localized("Health insight empty")
        }

        let standingPercent = Int((standingRatio * 100).rounded())

        if standingPercent >= 35 {
            return AppStrings.format("Health insight strong %d", standingPercent)
        }

        if standingPercent >= 20 {
            return AppStrings.format("Health insight balanced %d %d", standingPercent, standTransitions)
        }

        return AppStrings.format("Health insight low %d", standingPercent)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))

        guard minutes >= 60 else {
            return AppStrings.format("Duration minutes %d", minutes)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return AppStrings.format("Duration hours %d", hours)
        }

        return AppStrings.format("Duration hours minutes %d %d", hours, remainingMinutes)
    }
}

@MainActor
final class HealthStatsStore: NSObject, ObservableObject {
    static let shared = HealthStatsStore()

    @Published private(set) var days: [HealthStatsDay]
    @Published private(set) var lastUpdated = Date()

    private struct ActiveSession {
        let deskID: UUID
        var deskName: String
        var posture: HealthPosture
        var startedAt: Date
        var lastRecordedAt: Date
    }

    private enum Key {
        static let days = "healthStatsDays"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var activeSession: ActiveSession?
    private var persistenceTimer: Timer?

    private override init() {
        defaults = .standard
        DefaultsMigration.migrateIfNeeded(to: defaults)
        calendar = .autoupdatingCurrent
        days = defaults.healthStatsDays(forKey: Key.days)

        super.init()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        persistenceTimer?.invalidate()
    }

    var isTracking: Bool {
        activeSession != nil
    }

    func recordActiveDesk(
        id: UUID,
        name: String,
        height: Float?,
        sittingHeight: Float,
        standingHeight: Float,
        at date: Date = Date()
    ) {
        let posture = HealthPosture.classify(
            height: height,
            sittingHeight: sittingHeight,
            standingHeight: standingHeight
        )
        let deskName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "IDASEN Desk"

        guard var session = activeSession else {
            activeSession = ActiveSession(
                deskID: id,
                deskName: deskName,
                posture: posture,
                startedAt: date,
                lastRecordedAt: date
            )
            addSessionStart(on: date)
            schedulePersistenceTimer()
            save()
            return
        }

        if session.deskID != id {
            flushActiveSession(at: date)
            activeSession = ActiveSession(
                deskID: id,
                deskName: deskName,
                posture: posture,
                startedAt: date,
                lastRecordedAt: date
            )
            addSessionStart(on: date)
            schedulePersistenceTimer()
            save()
            return
        }

        let previousPosture = session.posture
        flushActiveSession(at: date)

        session = activeSession ?? session
        session.deskName = deskName
        session.posture = posture
        session.lastRecordedAt = max(session.lastRecordedAt, date)
        activeSession = session

        if previousPosture != .standing, posture == .standing {
            addStandTransition(on: date)
        }
    }

    func endSession(at date: Date = Date()) {
        flushActiveSession(at: date)
        activeSession = nil
        persistenceTimer?.invalidate()
        persistenceTimer = nil
        save()
    }

    func summary(for period: HealthStatsPeriod, now: Date = Date()) -> HealthStatsSummary {
        let interval = period.interval(containing: now, calendar: calendar)
        var dayMap = Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.day), $0) })

        if let activeSession {
            Self.applyInterval(
                from: activeSession.lastRecordedAt,
                to: now,
                posture: activeSession.posture,
                calendar: calendar,
                dayMap: &dayMap
            )
        }

        var buckets = [HealthStatsDay]()
        var cursor = interval.start

        while cursor < interval.end {
            let dayStart = calendar.startOfDay(for: cursor)
            buckets.append(dayMap[dayStart] ?? HealthStatsDay(day: dayStart))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
        }

        return HealthStatsSummary(
            period: period,
            startDate: interval.start,
            endDate: interval.end,
            days: buckets
        )
    }

    func reset() {
        days = []

        if var activeSession {
            let now = Date()
            activeSession.startedAt = now
            activeSession.lastRecordedAt = now
            self.activeSession = activeSession
            addSessionStart(on: now)
        }

        save()
    }

    @objc private func systemWillSleep() {
        endSession()
    }

    private func schedulePersistenceTimer() {
        guard persistenceTimer == nil else {
            return
        }

        let timer = Timer(fire: Date().addingTimeInterval(60), interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushActiveSession(at: Date())
                self?.save()
            }
        }
        timer.tolerance = 10
        persistenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func flushActiveSession(at date: Date) {
        guard var session = activeSession else {
            return
        }

        guard date > session.lastRecordedAt else {
            return
        }

        addInterval(from: session.lastRecordedAt, to: date, posture: session.posture)
        session.lastRecordedAt = date
        activeSession = session
    }

    private func addSessionStart(on date: Date) {
        let dayStart = calendar.startOfDay(for: date)
        var day = day(for: dayStart)
        day.sessions += 1
        day.firstSeen = minDate(day.firstSeen, date)
        day.lastSeen = maxDate(day.lastSeen, date)
        set(day)
        lastUpdated = date
    }

    private func addStandTransition(on date: Date) {
        let dayStart = calendar.startOfDay(for: date)
        var day = day(for: dayStart)
        day.standTransitions += 1
        day.firstSeen = minDate(day.firstSeen, date)
        day.lastSeen = maxDate(day.lastSeen, date)
        set(day)
        lastUpdated = date
    }

    private func addInterval(from start: Date, to end: Date, posture: HealthPosture) {
        var dayMap = Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.day), $0) })
        Self.applyInterval(from: start, to: end, posture: posture, calendar: calendar, dayMap: &dayMap)
        days = dayMap.values.sorted { $0.day < $1.day }
        pruneOldDays()
        lastUpdated = end
    }

    private func day(for dayStart: Date) -> HealthStatsDay {
        if let existing = days.first(where: { calendar.isDate($0.day, inSameDayAs: dayStart) }) {
            return existing
        }

        return HealthStatsDay(day: dayStart)
    }

    private func set(_ day: HealthStatsDay) {
        let dayStart = calendar.startOfDay(for: day.day)

        if let index = days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: dayStart) }) {
            days[index] = day
        } else {
            days.append(day)
        }

        days.sort { $0.day < $1.day }
        pruneOldDays()
    }

    private func pruneOldDays() {
        guard let cutoff = calendar.date(byAdding: .day, value: -180, to: calendar.startOfDay(for: Date())) else {
            return
        }

        days.removeAll { $0.day < cutoff }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: Key.days)
        }

        lastUpdated = Date()
    }

    private static func applyInterval(
        from start: Date,
        to end: Date,
        posture: HealthPosture,
        calendar: Calendar,
        dayMap: inout [Date: HealthStatsDay]
    ) {
        guard end > start else {
            return
        }

        var cursor = start

        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let segmentEnd = min(end, nextDay)
            let seconds = segmentEnd.timeIntervalSince(cursor)

            guard seconds > 0 else {
                break
            }

            var day = dayMap[dayStart] ?? HealthStatsDay(day: dayStart)
            day.workSeconds += seconds

            switch posture {
            case .sitting:
                day.sittingSeconds += seconds
            case .standing:
                day.standingSeconds += seconds
            case .transition:
                day.transitionSeconds += seconds
            }

            day.firstSeen = minDate(day.firstSeen, cursor)
            day.lastSeen = maxDate(day.lastSeen, segmentEnd)
            dayMap[dayStart] = day
            cursor = segmentEnd
        }
    }

    private static func minDate(_ first: Date?, _ second: Date) -> Date {
        guard let first else {
            return second
        }

        return min(first, second)
    }

    private static func maxDate(_ first: Date?, _ second: Date) -> Date {
        guard let first else {
            return second
        }

        return max(first, second)
    }

    private func minDate(_ first: Date?, _ second: Date) -> Date {
        Self.minDate(first, second)
    }

    private func maxDate(_ first: Date?, _ second: Date) -> Date {
        Self.maxDate(first, second)
    }
}

private extension UserDefaults {
    func healthStatsDays(forKey key: String) -> [HealthStatsDay] {
        guard let data = data(forKey: key),
              let days = try? JSONDecoder().decode([HealthStatsDay].self, from: data) else {
            return []
        }

        return days.sorted { $0.day < $1.day }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
