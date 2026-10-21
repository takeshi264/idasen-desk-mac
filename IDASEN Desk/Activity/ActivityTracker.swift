import Foundation
import Observation

/// Samples posture and presence, feeds the stats, and decides when to remind.
@MainActor
@Observable
final class ActivityTracker {
    /// Reminders repeat at this interval while the person keeps ignoring them.
    static let repeatInterval: TimeInterval = 15 * 60
    static let sampleInterval: Duration = .seconds(10)

    private(set) var posture: Posture?
    private(set) var streak: TimeInterval = 0

    @ObservationIgnored private let desk: DeskManager
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let store: ActivityStore
    @ObservationIgnored private let reminders: ReminderPresenter
    @ObservationIgnored private let presence: PresenceMonitor
    @ObservationIgnored private let sampler = RepeatingTask()
    @ObservationIgnored private var tracker = PostureTracker()
    @ObservationIgnored private var lastSample: Date?
    @ObservationIgnored private var lastReminder: Date?
    @ObservationIgnored private var snoozedUntil: Date?

    init(desk: DeskManager, preferences: Preferences, store: ActivityStore, reminders: ReminderPresenter, presence: PresenceMonitor) {
        self.desk = desk
        self.preferences = preferences
        self.store = store
        self.reminders = reminders
        self.presence = presence

        reminders.onResponse = { [weak self] kind, response in
            self?.handle(kind, response)
        }
    }

    func start() {
        sampler.start(every: Self.sampleInterval, fireImmediately: true) { [weak self] in
            self?.sample()
        }
    }

    func stop() {
        sampler.stop()
        store.save()
    }

    /// For the settings "Send test reminder" button.
    func sendTestReminder() {
        reminders.present(.stand, after: TimeInterval(preferences.sitReminderMinutes * 60))
    }

    private func sample(at now: Date = Date()) {
        let elapsed = lastSample.map { now.timeIntervalSince($0) } ?? 0
        lastSample = now

        let observed = desk.height.map {
            Posture.classify(height: $0, sittingHeight: preferences.sittingHeight, standingHeight: preferences.standingHeight)
        }
        let isPresent = presence.isPresent

        if isPresent, let observed, elapsed > 0, elapsed <= PostureTracker.maximumSampleGap {
            store.add(observed, seconds: elapsed, at: now)
        }

        let previousRun = tracker.runID
        let event = tracker.record(posture: observed, isPresent: isPresent, at: now)

        if case .switched(from: .sitting, to: .standing) = event {
            store.recordStandUp(at: now)
        }

        if tracker.runID != previousRun {
            lastReminder = nil
            snoozedUntil = nil
            reminders.clear()
        }

        posture = tracker.posture
        streak = tracker.streak

        remindIfNeeded(isPresent: isPresent, now: now)
    }

    private func remindIfNeeded(isPresent: Bool, now: Date) {
        guard isPresent, let posture = tracker.posture else {
            return
        }

        let (enabled, minutes, kind): (Bool, Int, ReminderPresenter.Kind) = switch posture {
        case .sitting:
            (preferences.sitReminderEnabled, preferences.sitReminderMinutes, .stand)
        case .standing:
            (preferences.standReminderEnabled, preferences.standReminderMinutes, .sit)
        }

        guard enabled, tracker.streak >= TimeInterval(minutes * 60) else {
            return
        }

        if let snoozedUntil, now < snoozedUntil {
            return
        }

        if let lastReminder, now.timeIntervalSince(lastReminder) < Self.repeatInterval, snoozedUntil == nil {
            return
        }

        snoozedUntil = nil
        lastReminder = now
        reminders.present(kind, after: tracker.streak)
    }

    private func handle(_ kind: ReminderPresenter.Kind, _ response: ReminderPresenter.Response) {
        switch response {
        case .move:
            Task {
                // The desk may be reconnecting if the Mac just woke up.
                guard await desk.waitUntilReady(timeout: .seconds(10)) else {
                    return
                }
                desk.move(to: kind == .stand ? .stand : .sit)
            }
        case .snooze:
            snoozedUntil = Date().addingTimeInterval(TimeInterval(ReminderPresenter.snoozeMinutes * 60))
        }
    }

    #if DEBUG
    func setPreviewState(posture: Posture?, streak: TimeInterval) {
        self.posture = posture
        self.streak = streak
    }
    #endif
}
