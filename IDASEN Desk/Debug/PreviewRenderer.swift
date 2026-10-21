#if DEBUG
import AppKit
import SwiftUI

/// Renders the UI with fake desk data to PNG files, for screenshots and visual checks
/// without hardware: `"IDASEN Desk" --render-previews <output-dir>`.
@MainActor
enum PreviewRenderer {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--render-previews")
    }

    static func run() {
        let arguments = CommandLine.arguments
        let directory = arguments.firstIndex(of: "--render-previews")
            .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            .map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory())

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let environment = AppEnvironment.shared
        seed(environment)

        let desk = environment.desk
        let geometry = environment.preferences.geometry
        let raw = { (height: Double) in geometry.raw(height: height) }

        let menuStates: [(String, () -> Void)] = [
            ("menu-connected", {
                desk.setPreviewState(status: .connected, heightRaw: raw(72))
                environment.tracker.setPreviewState(posture: .sitting, streak: 32 * 60)
            }),
            ("menu-standing", {
                desk.setPreviewState(status: .connected, heightRaw: raw(110))
                environment.tracker.setPreviewState(posture: .standing, streak: 14 * 60)
            }),
            ("menu-moving", {
                desk.setPreviewState(status: .connected, heightRaw: raw(93.4), target: .preset(.stand), direction: .up, moveStart: 72)
                environment.tracker.setPreviewState(posture: .sitting, streak: 32 * 60)
            }),
            ("menu-adjusted", {
                desk.setPreviewState(status: .connected, heightRaw: raw(98.5))
                environment.tracker.setPreviewState(posture: .standing, streak: 3 * 60)
            }),
            ("menu-stalled", {
                desk.setPreviewState(status: .connected, heightRaw: raw(88), stalled: true)
            }),
            ("menu-setup", {
                desk.setPreviewState(status: .noDesk, heightRaw: nil, discovered: [
                    DiscoveredDesk(id: UUID(), name: "Desk 4754", rssi: -58, isKnown: false),
                    DiscoveredDesk(id: UUID(), name: "Desk 1093", rssi: -81, isKnown: false)
                ], isScanning: true)
            }),
            ("menu-searching", {
                desk.setPreviewState(status: .searching, heightRaw: nil)
            }),
            ("menu-bluetooth-off", {
                desk.setPreviewState(status: .bluetoothOff, heightRaw: nil)
            })
        ]

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"

            for (name, configure) in menuStates {
                configure()
                render(MenuBarView().appEnvironment(environment), width: 340, appearance: appearance, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }

        desk.setPreviewState(status: .connected, heightRaw: raw(72))

        let tabs: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettingsView())),
            ("heights", AnyView(HeightSettingsView())),
            ("desks", AnyView(DeskSettingsView())),
            ("reminders", AnyView(ReminderSettingsView())),
            ("controls", AnyView(ControlSettingsView())),
            ("activity", AnyView(ActivitySettingsView()))
        ]

        for (name, view) in tabs {
            render(
                view.appEnvironment(environment).frame(width: 540, height: 520),
                width: 540,
                appearance: .aqua,
                to: directory.appendingPathComponent("settings-\(name).png")
            )
        }

        for state in [0.0, 0.5, 1.0] {
            for direction in [MovingDirection.none, .up] {
                let image = DeskGlyph.image(fraction: state, direction: direction)
                save(image, scale: 4, to: directory.appendingPathComponent("glyph-\(Int(state * 100))-\(direction).png"))
            }
        }
        save(DeskGlyph.image(fraction: nil, direction: .none), scale: 4, to: directory.appendingPathComponent("glyph-disconnected.png"))

        print("Rendered previews to \(directory.path)")
        exit(0)
    }

    private static func seed(_ environment: AppEnvironment) {
        let preferences = environment.preferences
        preferences.sittingHeight = 72
        preferences.standingHeight = 110
        preferences.customPresets = [CustomPreset(name: "Focus", height: 104)]
        preferences.knownDesks = [
            KnownDesk(id: UUID(), name: "Desk 4754", lastSeen: Date()),
            KnownDesk(id: UUID(), name: "Home Office", lastSeen: Date().addingTimeInterval(-3 * 86400))
        ]
        preferences.sitReminderEnabled = true
        preferences.doubleTapToSitStand = true
        preferences.hotKeys = [.toggle: HotKey(keyCode: 126, modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue, display: "⌃⌥⌘↑")]

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<30).compactMap { offset -> ActivityDay? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            if calendar.isDateInWeekend(day) && offset > 0 {
                return nil
            }
            let seed = Double((offset * 37) % 11) / 10
            return ActivityDay(
                day: day,
                sittingSeconds: (4.5 + seed * 1.5) * 3600,
                standingSeconds: (0.8 + seed * 1.4) * 3600,
                standTransitions: 3 + offset % 4
            )
        }
        environment.activity.setPreviewDays(days.reversed())
    }

    private static func render<V: View>(_ view: V, width: CGFloat, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting

        let size = hosting.fittingSize
        window.setContentSize(NSSize(width: width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return
        }

        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func save(_ image: NSImage, scale: CGFloat, to url: URL) {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
