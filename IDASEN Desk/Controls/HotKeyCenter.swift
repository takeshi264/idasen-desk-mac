import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts via Carbon hot keys, which need no accessibility
/// permission and work inside the App Sandbox.
@MainActor
final class HotKeyCenter {
    private var registrations = [HotKeyAction: EventHotKeyRef]()
    private var handlerRef: EventHandlerRef?
    private var actions = [UInt32: HotKeyAction]()

    var onAction: ((HotKeyAction) -> Void)?

    private static let signature: OSType = 0x4944_534B // "IDSK"

    /// Registers the given shortcuts, replacing earlier ones. Returns actions whose
    /// shortcut is already taken by another app.
    @discardableResult
    func register(_ hotKeys: [HotKeyAction: HotKey]) -> Set<HotKeyAction> {
        unregisterAll()
        installHandlerIfNeeded()

        var conflicts = Set<HotKeyAction>()

        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let hotKey = hotKeys[action] else {
                continue
            }

            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                hotKey.keyCode,
                Self.carbonModifiers(from: NSEvent.ModifierFlags(rawValue: hotKey.modifiers)),
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &ref
            )

            if status == noErr, let ref {
                registrations[action] = ref
                actions[id] = action
            } else {
                conflicts.insert(action)
            }
        }

        return conflicts
    }

    func unregisterAll() {
        registrations.values.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else {
                return OSStatus(eventNotHandledErr)
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return status
            }

            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                center.handle(id: hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }

    private func handle(id: UInt32) {
        if let action = actions[id] {
            onAction?(action)
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// "⌃⌥⌘↑"-style description of a key event, or nil if it can't be a shortcut.
    static func hotKey(from event: NSEvent) -> HotKey? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = Int(event.keyCode)
        let isFunctionKey = functionKeyNames[keyCode] != nil

        // Plain keys would swallow ordinary typing system-wide.
        guard isFunctionKey || !modifiers.subtracting(.shift).isEmpty else {
            return nil
        }

        guard let key = keyName(for: event) else {
            return nil
        }

        var display = ""
        if modifiers.contains(.control) { display += "⌃" }
        if modifiers.contains(.option) { display += "⌥" }
        if modifiers.contains(.shift) { display += "⇧" }
        if modifiers.contains(.command) { display += "⌘" }
        display += key

        return HotKey(keyCode: UInt32(keyCode), modifiers: modifiers.rawValue, display: display)
    }

    private static func keyName(for event: NSEvent) -> String? {
        let keyCode = Int(event.keyCode)

        if let name = specialKeyNames[keyCode] ?? functionKeyNames[keyCode] {
            return name
        }

        guard let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }

        return characters
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
    ]

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]
}
