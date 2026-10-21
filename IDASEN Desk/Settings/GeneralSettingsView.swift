import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemStatus = LoginItem.status

    var body: some View {
        @Bindable var preferences = preferences

        SettingsForm {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? LoginItem.setEnabled(enabled)
                        loginItemStatus = LoginItem.status
                        launchAtLogin = LoginItem.isEnabled
                    }

                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("macOS needs your approval in Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
            } footer: {
                Text("Presets, reminders and shortcuts only work while the app is running.")
            }

            Section {
                Toggle("Show height in the menu bar", isOn: $preferences.showHeightInMenuBar)

                Picker("Units", selection: $preferences.isMetric) {
                    Text("Centimetres").tag(true)
                    Text("Inches").tag(false)
                }
            }

            Section {
                LabeledContent("Version") {
                    Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
                Link(destination: URL(string: "https://github.com/takeshi264/idasen-desk-mac")!) {
                    Text("Project on GitHub")
                }
            } footer: {
                Text("Not affiliated with IKEA or Linak. Everything stays on this Mac.")
            }
        }
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            loginItemStatus = LoginItem.status
        }
    }
}
