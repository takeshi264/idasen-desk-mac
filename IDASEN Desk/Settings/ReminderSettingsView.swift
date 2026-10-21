import SwiftUI

struct ReminderSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ReminderPresenter.self) private var reminders
    @Environment(ActivityTracker.self) private var tracker

    var body: some View {
        @Bindable var preferences = preferences

        SettingsForm {
            Section {
                Toggle("Remind me to stand", isOn: $preferences.sitReminderEnabled)
                Picker("After sitting for", selection: $preferences.sitReminderMinutes) {
                    ForEach(Preferences.sitReminderChoices, id: \.self) { minutes in
                        Text(verbatim: Formatters.duration(TimeInterval(minutes * 60))).tag(minutes)
                    }
                }
                .disabled(!preferences.sitReminderEnabled)
            } footer: {
                Text("Only time at your Mac counts. Being away for 5 minutes counts as a break.")
            }

            Section {
                Toggle("Remind me to sit", isOn: $preferences.standReminderEnabled)
                Picker("After standing for", selection: $preferences.standReminderMinutes) {
                    ForEach(Preferences.standReminderChoices, id: \.self) { minutes in
                        Text(verbatim: Formatters.duration(TimeInterval(minutes * 60))).tag(minutes)
                    }
                }
                .disabled(!preferences.standReminderEnabled)
            }

            Section {
                notificationStatus

                Button("Send Test Reminder") {
                    tracker.sendTestReminder()
                }
            } header: {
                Text("Delivery")
            } footer: {
                Text("Reminders never move the desk on their own. Choose Stand Up in the reminder to raise it.")
            }
        }
        .task {
            await reminders.refreshAuthorization()
        }
        .onChange(of: preferences.sitReminderEnabled) { _, enabled in
            requestNotificationsIfNeeded(enabled)
        }
        .onChange(of: preferences.standReminderEnabled) { _, enabled in
            requestNotificationsIfNeeded(enabled)
        }
    }

    @ViewBuilder
    private var notificationStatus: some View {
        switch reminders.authorization {
        case .authorized, .provisional, .ephemeral:
            Label("Reminders arrive as notifications.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .notDetermined:
            HStack {
                Text("Reminders can arrive as notifications.")
                Spacer()
                Button("Allow Notifications") {
                    Task { await reminders.requestAuthorization() }
                }
            }
        case .denied:
            HStack {
                Text("Notifications are off, so reminders appear in a small panel instead.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Notification Settings") {
                    SystemSettings.open(SystemSettings.notifications)
                }
            }
        @unknown default:
            EmptyView()
        }
    }

    private func requestNotificationsIfNeeded(_ enabled: Bool) {
        guard enabled, reminders.authorization == .notDetermined else {
            return
        }

        Task { await reminders.requestAuthorization() }
    }
}
