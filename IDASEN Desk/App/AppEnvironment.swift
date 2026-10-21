import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// Builds and owns the app's long-lived objects.
@MainActor
@Observable
final class AppEnvironment {
    static let shared: AppEnvironment = {
        #if DEBUG
        if PreviewRenderer.isRequested {
            return AppEnvironment(isLive: false)
        }
        #endif
        return AppEnvironment(isLive: !ProcessInfo.isRunningTests)
    }()

    let preferences: Preferences
    let desk: DeskManager
    let activity: ActivityStore
    let reminders: ReminderPresenter
    let tracker: ActivityTracker

    /// Shortcuts another app already owns.
    private(set) var hotKeyConflicts = Set<HotKeyAction>()

    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored private let isLive: Bool

    init(isLive: Bool) {
        self.isLive = isLive

        let defaults = isLive ? UserDefaults.standard : UserDefaults(suiteName: "preview.\(UUID().uuidString)")!
        preferences = Preferences(defaults: defaults)
        desk = DeskManager(preferences: preferences, startsBluetooth: isLive)
        activity = ActivityStore(defaults: defaults)
        reminders = ReminderPresenter(usesNotifications: isLive)
        tracker = ActivityTracker(
            desk: desk,
            preferences: preferences,
            store: activity,
            reminders: reminders,
            presence: PresenceMonitor()
        )

        hotKeys.onAction = { [weak self] action in
            self?.perform(action)
        }
    }

    func start() {
        guard isLive else {
            return
        }

        tracker.start()
        hotKeyConflicts = hotKeys.register(preferences.hotKeys)

        // Reminders may already be on from 1.x, before notifications were used.
        Task {
            await reminders.refreshAuthorization()
            if preferences.sitReminderEnabled || preferences.standReminderEnabled, reminders.authorization == .notDetermined {
                await reminders.requestAuthorization()
            }
        }
    }

    func shutDown() {
        desk.stop()
        tracker.stop()
    }

    func setHotKey(_ hotKey: HotKey?, for action: HotKeyAction) {
        preferences.hotKeys[action] = hotKey
        if isLive {
            hotKeyConflicts = hotKeys.register(preferences.hotKeys)
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .toggle:
            desk.toggleSitStand()
        case .sit:
            desk.moveOrStop(.sit)
        case .stand:
            desk.moveOrStop(.stand)
        }
    }
}

extension View {
    func appEnvironment(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment)
            .environment(environment.preferences)
            .environment(environment.desk)
            .environment(environment.activity)
            .environment(environment.reminders)
            .environment(environment.tracker)
    }
}

/// Wraps `SMAppService` so the toggle reflects what macOS actually has.
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
