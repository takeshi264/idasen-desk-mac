import AppKit
import SwiftUI

@main
struct IDASENDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .appEnvironment(environment)
        } label: {
            MenuBarLabel()
                .appEnvironment(environment)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .appEnvironment(environment)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if PreviewRenderer.isRequested {
            PreviewRenderer.run()
            return
        }
        #endif

        AppEnvironment.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.shutDown()
    }
}
