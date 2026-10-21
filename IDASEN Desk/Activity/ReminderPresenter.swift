import AppKit
import Observation
import SwiftUI
import UserNotifications

/// Shows posture reminders as system notifications, or as a small floating panel that
/// never takes keyboard focus when notifications are not allowed.
@MainActor
@Observable
final class ReminderPresenter {
    enum Kind: String {
        /// Been sitting too long; suggests standing.
        case stand
        /// Been standing too long; suggests sitting.
        case sit
    }

    enum Response {
        case move
        case snooze
    }

    static let snoozeMinutes = 10

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored var onResponse: ((Kind, Response) -> Void)?
    @ObservationIgnored private let delegate = NotificationDelegate()
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private let usesNotifications: Bool

    private static let notificationID = "posture-reminder"

    init(usesNotifications: Bool = true) {
        self.usesNotifications = usesNotifications
        guard usesNotifications else {
            return
        }

        delegate.owner = self
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([
            Self.category(.stand, action: String(localized: "Stand Up")),
            Self.category(.sit, action: String(localized: "Sit Down"))
        ])

        Task {
            await refreshAuthorization()
        }
    }

    var canUseNotifications: Bool {
        authorization == .authorized || authorization == .provisional
    }

    func refreshAuthorization() async {
        guard usesNotifications else {
            return
        }

        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        guard usesNotifications else {
            return
        }

        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
    }

    func present(_ kind: Kind, after duration: TimeInterval) {
        let title = kind == .stand ? String(localized: "Time to stand up") : String(localized: "Time to sit down")
        let elapsed = Formatters.duration(duration)
        let body = kind == .stand
            ? String(localized: "You've been sitting for \(elapsed).")
            : String(localized: "You've been standing for \(elapsed).")

        if canUseNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = kind.rawValue

            let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        } else {
            showPanel(kind: kind, title: title, body: body)
        }
    }

    func clear() {
        if usesNotifications {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        }
        panel?.close()
        panel = nil
    }

    fileprivate func respond(_ kind: Kind, _ response: Response) {
        clear()
        onResponse?(kind, response)
    }

    private static func category(_ kind: Kind, action: String) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: kind.rawValue,
            actions: [
                UNNotificationAction(identifier: "move", title: action),
                UNNotificationAction(identifier: "snooze", title: String(localized: "Snooze \(snoozeMinutes) min"))
            ],
            intentIdentifiers: []
        )
    }

    // MARK: - Fallback panel

    private func showPanel(kind: Kind, title: String, body: String) {
        panel?.close()

        let view = ReminderPanelView(
            kind: kind,
            title: title,
            message: body,
            move: { [weak self] in self?.respond(kind, .move) },
            snooze: { [weak self] in self?.respond(kind, .snooze) },
            dismiss: { [weak self] in self?.clear() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width - 12, y: frame.maxY - 12))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct ReminderPanelView: View {
    let kind: ReminderPresenter.Kind
    let title: String
    let message: String
    let move: () -> Void
    let snooze: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind == .stand ? "figure.stand" : "chair")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }

            HStack {
                Spacer()
                Button("Snooze \(ReminderPresenter.snoozeMinutes) min", action: snooze)
                Button(kind == .stand ? "Stand Up" : "Sit Down", action: move)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .padding(8)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var owner: ReminderPresenter?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let kind = ReminderPresenter.Kind(rawValue: category) else {
                    return
                }

                switch action {
                case "move":
                    self?.owner?.respond(kind, .move)
                case "snooze":
                    self?.owner?.respond(kind, .snooze)
                default:
                    break
                }
            }
        }

        completionHandler()
    }
}
