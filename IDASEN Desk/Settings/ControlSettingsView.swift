import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ControlSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = preferences

        SettingsForm {
            Section {
                ShortcutRow(action: .toggle, title: Text("Toggle sit/stand"))
                ShortcutRow(action: .stand, title: Text("Stand up"))
                ShortcutRow(action: .sit, title: Text("Sit down"))
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Work in any app. Press a shortcut again while the desk is moving to stop it.")
            }

            Section {
                Toggle(isOn: $preferences.doubleTapToSitStand) {
                    Text("Double-tap the desk handle")
                    Text("Two quick taps up go to standing height, two taps down go to sitting height.")
                }
            } header: {
                Text("Desk Handle")
            }

            Section {
                HStack(alignment: .top) {
                    Text("Stand Up, Sit Down, Toggle Sit/Stand, Move Desk to Height and Get Desk Height are available in Shortcuts and Siri.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                }
            } header: {
                Text("Shortcuts")
            }
        }
    }
}

private struct ShortcutRow: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AppEnvironment.self) private var environment

    let action: HotKeyAction
    let title: Text

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                if environment.hotKeyConflicts.contains(action) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(Text("Another app is already using this shortcut."))
                }

                ShortcutRecorder(hotKey: preferences.hotKeys[action]) { hotKey in
                    environment.setHotKey(hotKey, for: action)
                }
            }
        } label: {
            title
        }
    }
}

/// Click, then press a key combination. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    let hotKey: HotKey?
    let onChange: (HotKey?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Group {
                    if isRecording {
                        Text("Type shortcut…")
                            .foregroundStyle(.tint)
                    } else if let hotKey {
                        Text(verbatim: hotKey.display)
                    } else {
                        Text("Record Shortcut")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 110)
            }

            if hotKey != nil, !isRecording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(Text("Clear"))
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty

            switch keyCode {
            case kVK_Escape:
                stopRecording()
            case kVK_Delete where !hasModifiers, kVK_ForwardDelete where !hasModifiers:
                onChange(nil)
                stopRecording()
            default:
                guard let hotKey = HotKeyCenter.hotKey(from: event) else {
                    NSSound.beep()
                    return nil
                }
                onChange(hotKey)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
