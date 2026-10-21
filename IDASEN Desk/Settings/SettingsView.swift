import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general
    case heights
    case desks
    case reminders
    case controls
    case activity

    static let storageKey = "settingsTab"
}

struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            HeightSettingsView()
                .tabItem { Label("Heights", systemImage: "arrow.up.and.down") }
                .tag(SettingsTab.heights)

            DeskSettingsView()
                .tabItem { Label("Desks", systemImage: "table.furniture") }
                .tag(SettingsTab.desks)

            ReminderSettingsView()
                .tabItem { Label("Reminders", systemImage: "bell") }
                .tag(SettingsTab.reminders)

            ControlSettingsView()
                .tabItem { Label("Controls", systemImage: "keyboard") }
                .tag(SettingsTab.controls)

            ActivitySettingsView()
                .tabItem { Label("Activity", systemImage: "chart.bar") }
                .tag(SettingsTab.activity)
        }
        .frame(width: 540, height: 500)
    }
}

/// Shared look for every settings tab.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }
}
