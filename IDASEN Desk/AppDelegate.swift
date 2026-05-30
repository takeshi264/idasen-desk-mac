import AppKit
import SwiftUI

@main
struct IDASENDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DeskAppModel()
    @StateObject private var preferences = Preferences.shared

    var body: some Scene {
        MenuBarExtra {
            DeskControlView(model: model, preferences: preferences)
                .environment(\.locale, preferences.appLanguage.locale)
                .id(preferences.appLanguage.rawValue)
        } label: {
            MenuBarStatusIcon(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView(model: model, preferences: preferences)
                .environment(\.locale, preferences.appLanguage.locale)
                .id(preferences.appLanguage.rawValue)
                .frame(width: 760, height: 540)
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarStatusIcon: View {
    @ObservedObject var model: DeskAppModel

    var body: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .help("IDASEN Desk")
    }

    private var systemImage: String {
        switch model.movingDirection {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .none:
            return model.isConnected ? "arrow.up.and.down" : "dot.radiowaves.left.and.right"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if Preferences.shared.isFirstLaunch {
            Preferences.shared.isFirstLaunch = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HealthStatsStore.shared.endSession()
    }
}
