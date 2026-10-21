import Foundation
import Observation

struct KnownDesk: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var lastSeen: Date
}

struct CustomPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    /// Real desktop height in centimetres.
    var height: Double
}

enum PresetID: Hashable {
    case sit
    case stand
    case custom(UUID)
}

enum HotKeyAction: String, CaseIterable, Codable, Identifiable {
    case toggle
    case sit
    case stand

    var id: String {
        rawValue
    }
}

struct HotKey: Codable, Equatable {
    /// Carbon virtual key code.
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, limited to ⌘⌥⌃⇧.
    var modifiers: UInt
    /// Human-readable form captured when the shortcut was recorded, e.g. "⌃⌥↑".
    var display: String
}

@MainActor
@Observable
final class Preferences {
    static let maximumCustomPresets = 4
    static let sitReminderChoices = [30, 45, 60, 90]
    static let standReminderChoices = [15, 30, 45, 60]

    private enum Key {
        // Keys from 1.x are kept so existing settings carry over.
        static let standingHeight = "standingPositionValue"
        static let sittingHeight = "sittingPositionValue"
        static let legacyPositionOffset = "positionOffsetValue"
        static let isMetric = "isMetric"
        static let doubleTap = "doubleTapToSitStandKey"
        static let knownDesks = "knownDesks"
        static let activeDeskID = "activeDeskID"
        static let sitReminderEnabled = "automaticStandEnabledKey"

        static let deskBaseHeight = "deskBaseHeight"
        static let customPresets = "customPresets"
        static let showHeightInMenuBar = "showHeightInMenuBar"
        static let sitReminderMinutes = "sitReminderMinutes"
        static let standReminderEnabled = "standReminderEnabled"
        static let standReminderMinutes = "standReminderMinutes"
        static let hotKeys = "hotKeys"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var sittingHeight: Double {
        didSet { defaults.set(sittingHeight, forKey: Key.sittingHeight) }
    }

    var standingHeight: Double {
        didSet { defaults.set(standingHeight, forKey: Key.standingHeight) }
    }

    var customPresets: [CustomPreset] {
        didSet { defaults.setEncoded(customPresets, forKey: Key.customPresets) }
    }

    /// Real height of the desktop at the desk's lowest position. Set by calibration.
    var deskBaseHeight: Double {
        didSet { defaults.set(deskBaseHeight, forKey: Key.deskBaseHeight) }
    }

    var isMetric: Bool {
        didSet { defaults.set(isMetric, forKey: Key.isMetric) }
    }

    var showHeightInMenuBar: Bool {
        didSet { defaults.set(showHeightInMenuBar, forKey: Key.showHeightInMenuBar) }
    }

    var doubleTapToSitStand: Bool {
        didSet { defaults.set(doubleTapToSitStand, forKey: Key.doubleTap) }
    }

    var sitReminderEnabled: Bool {
        didSet { defaults.set(sitReminderEnabled, forKey: Key.sitReminderEnabled) }
    }

    var sitReminderMinutes: Int {
        didSet { defaults.set(sitReminderMinutes, forKey: Key.sitReminderMinutes) }
    }

    var standReminderEnabled: Bool {
        didSet { defaults.set(standReminderEnabled, forKey: Key.standReminderEnabled) }
    }

    var standReminderMinutes: Int {
        didSet { defaults.set(standReminderMinutes, forKey: Key.standReminderMinutes) }
    }

    var hotKeys: [HotKeyAction: HotKey] {
        didSet { defaults.setEncoded(hotKeys, forKey: Key.hotKeys) }
    }

    var knownDesks: [KnownDesk] {
        didSet { defaults.setEncoded(knownDesks, forKey: Key.knownDesks) }
    }

    /// The desk to prefer when more than one known desk is in range.
    var activeDeskID: UUID? {
        didSet { defaults.set(activeDeskID?.uuidString, forKey: Key.activeDeskID) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        DefaultsMigration.migrateIfNeeded(to: defaults)

        let hasLegacySettings = defaults.object(forKey: Key.standingHeight) != nil

        sittingHeight = defaults.double(forKey: Key.sittingHeight, default: 72)
        standingHeight = defaults.double(forKey: Key.standingHeight, default: 110)
        customPresets = defaults.decoded([CustomPreset].self, forKey: Key.customPresets) ?? []

        if let base = defaults.object(forKey: Key.deskBaseHeight) as? Double {
            deskBaseHeight = base
        } else if hasLegacySettings {
            // 1.x assumed 61.5 cm and showed an extra display-only offset on top.
            deskBaseHeight = 61.5 + defaults.double(forKey: Key.legacyPositionOffset, default: 0)
        } else {
            deskBaseHeight = DeskGeometry.defaultBaseHeight
        }

        isMetric = defaults.bool(forKey: Key.isMetric, default: Locale.current.measurementSystem == .metric)
        showHeightInMenuBar = defaults.bool(forKey: Key.showHeightInMenuBar, default: false)
        doubleTapToSitStand = defaults.bool(forKey: Key.doubleTap, default: false)
        sitReminderEnabled = defaults.bool(forKey: Key.sitReminderEnabled, default: false)
        sitReminderMinutes = defaults.integer(forKey: Key.sitReminderMinutes, default: 45)
        standReminderEnabled = defaults.bool(forKey: Key.standReminderEnabled, default: false)
        standReminderMinutes = defaults.integer(forKey: Key.standReminderMinutes, default: 30)
        hotKeys = defaults.decoded([HotKeyAction: HotKey].self, forKey: Key.hotKeys) ?? [:]
        knownDesks = defaults.decoded([KnownDesk].self, forKey: Key.knownDesks) ?? []
        activeDeskID = defaults.string(forKey: Key.activeDeskID).flatMap(UUID.init(uuidString:))
    }

    // MARK: - Heights

    var geometry: DeskGeometry {
        DeskGeometry(baseHeight: deskBaseHeight)
    }

    func height(for preset: PresetID) -> Double? {
        switch preset {
        case .sit:
            return sittingHeight
        case .stand:
            return standingHeight
        case .custom(let id):
            return customPresets.first { $0.id == id }?.height
        }
    }

    func setHeight(_ height: Double, for preset: PresetID) {
        let height = height.clamped(to: geometry.range)

        switch preset {
        case .sit:
            sittingHeight = height
        case .stand:
            standingHeight = height
        case .custom(let id):
            if let index = customPresets.firstIndex(where: { $0.id == id }) {
                customPresets[index].height = height
            }
        }
    }

    /// Re-anchors heights to a tape-measured value while keeping every preset at the
    /// same physical position, so pressing Sit still goes exactly where it used to.
    func calibrate(measuredHeight: Double, currentRaw: Int) {
        let newBase = measuredHeight - Double(currentRaw) / 100
        let delta = newBase - deskBaseHeight
        guard abs(delta) > 0.001 else {
            return
        }

        deskBaseHeight = newBase
        sittingHeight += delta
        standingHeight += delta
        for index in customPresets.indices {
            customPresets[index].height += delta
        }
    }

    // MARK: - Desks

    func rememberDesk(id: UUID, name: String?) {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = knownDesks.firstIndex(where: { $0.id == id }) {
            knownDesks[index].lastSeen = Date()
        } else {
            knownDesks.append(KnownDesk(id: id, name: name?.isEmpty == false ? name! : "IDASEN Desk", lastSeen: Date()))
        }

        knownDesks.sort { $0.lastSeen > $1.lastSeen }
        activeDeskID = id
    }

    func renameDesk(id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = knownDesks.firstIndex(where: { $0.id == id }) else {
            return
        }

        knownDesks[index].name = name
    }

    func forgetDesk(id: UUID) {
        knownDesks.removeAll { $0.id == id }
        if activeDeskID == id {
            activeDeskID = knownDesks.first?.id
        }
    }

    func deskName(for id: UUID?) -> String? {
        knownDesks.first { $0.id == id }?.name
    }
}

/// Copies settings saved under the bundle identifiers used by earlier builds.
enum DefaultsMigration {
    private static let legacyBundleIdentifiers = [
        "com.tom.idasen-desk",
        "com.adeptusastartes.idasen-desk"
    ]
    private static var hasRun = false

    static func migrateIfNeeded(to defaults: UserDefaults) {
        guard !hasRun, defaults == .standard else {
            return
        }

        hasRun = true

        for identifier in legacyBundleIdentifiers where Bundle.main.bundleIdentifier != identifier {
            guard let legacyDomain = UserDefaults.standard.persistentDomain(forName: identifier) else {
                continue
            }

            for (key, value) in legacyDomain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }
}

extension UserDefaults {
    func double(forKey key: String, default defaultValue: Double) -> Double {
        object(forKey: key) == nil ? defaultValue : double(forKey: key)
    }

    func integer(forKey key: String, default defaultValue: Int) -> Int {
        object(forKey: key) == nil ? defaultValue : integer(forKey: key)
    }

    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }

    func decoded<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    func setEncoded<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            set(data, forKey: key)
        }
    }
}
