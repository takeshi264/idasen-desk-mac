import AppKit
import CoreGraphics

/// Tells whether someone is actually at the Mac: recent input, screen unlocked, awake.
@MainActor
final class PresenceMonitor {
    /// No keyboard or mouse input for this long means the person stepped away.
    static let idleThreshold: TimeInterval = 3 * 60

    private var isScreenLocked = false
    private var isAsleep = false
    private var observers = [(NotificationCenter, NSObjectProtocol)]()

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.isAsleep = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isScreenLocked = false }
    }

    var isPresent: Bool {
        !isScreenLocked && !isAsleep && secondsSinceLastInput < Self.idleThreshold
    }

    var secondsSinceLastInput: TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else {
            return 0
        }

        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, update: @escaping @MainActor (PresenceMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self {
                    update(self)
                }
            }
        }
        observers.append((center, token))
    }
}
