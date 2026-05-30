import Combine
import Foundation
import ServiceManagement

struct KnownDesk: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var lastSeen: Date
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case japanese
    case traditionalChinese

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        case .traditionalChinese:
            return "繁體中文"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .japanese:
            return Locale(identifier: "ja")
        case .traditionalChinese:
            return Locale(identifier: "zh-Hant")
        }
    }
}

enum LoginItemController {
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static func setEnabled(_ isEnabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if isEnabled {
                guard service.status != .enabled, service.status != .requiresApproval else {
                    return
                }

                try service.register()
            } else {
                guard service.status != .notRegistered else {
                    return
                }

                try service.unregister()
            }
        } catch {
            return
        }
    }
}

enum DefaultsMigration {
    private static let legacyBundleIdentifiers = [
        "com.tom.idasen-desk",
        "com.adeptusastartes.idasen-desk"
    ]
    private static var hasRun = false

    static func migrateIfNeeded(to defaults: UserDefaults = .standard) {
        guard !hasRun else {
            return
        }

        hasRun = true

        for identifier in legacyBundleIdentifiers where Bundle.main.bundleIdentifier != identifier {
            guard let legacyDomain = UserDefaults.standard.persistentDomain(forName: identifier),
                  !legacyDomain.isEmpty else {
                continue
            }

            for (key, value) in legacyDomain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let standingPosition = "standingPositionValue"
        static let sittingPosition = "sittingPositionValue"
        static let automaticStandPerHour = "automaticStandValue"
        static let automaticStandInactivity = "automaticStandInactivityKey"
        static let automaticStandEnabled = "automaticStandEnabledKey"
        static let positionOffset = "positionOffsetValue"
        static let isMetric = "isMetric"
        static let doubleTapToSitStand = "doubleTapToSitStandKey"
        static let hasLaunched = "hasLaunched"
        static let knownDesks = "knownDesks"
        static let activeDeskID = "activeDeskID"
        static let appLanguage = "appLanguage"
    }

    private let defaults: UserDefaults

    @Published var standingPosition: Float {
        didSet {
            defaults.set(standingPosition, forKey: Key.standingPosition)
        }
    }

    @Published var sittingPosition: Float {
        didSet {
            defaults.set(sittingPosition, forKey: Key.sittingPosition)
        }
    }

    @Published var automaticStandPerHour: TimeInterval {
        didSet {
            defaults.set(automaticStandPerHour, forKey: Key.automaticStandPerHour)
            DeskMotionController.shared?.autoStand.update()
        }
    }

    @Published var automaticStandInactivity: TimeInterval {
        didSet {
            defaults.set(automaticStandInactivity, forKey: Key.automaticStandInactivity)
            DeskMotionController.shared?.autoStand.update()
        }
    }

    @Published var automaticStandEnabled: Bool {
        didSet {
            defaults.set(automaticStandEnabled, forKey: Key.automaticStandEnabled)
            DeskMotionController.shared?.autoStand.update()
        }
    }

    @Published var positionOffset: Float {
        didSet {
            defaults.set(positionOffset, forKey: Key.positionOffset)
        }
    }

    @Published var isMetric: Bool {
        didSet {
            defaults.set(isMetric, forKey: Key.isMetric)
        }
    }

    @Published var doubleTapToSitStand: Bool {
        didSet {
            defaults.set(doubleTapToSitStand, forKey: Key.doubleTapToSitStand)
        }
    }

    @Published var openAtLogin: Bool {
        didSet {
            LoginItemController.setEnabled(openAtLogin)
        }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
        }
    }

    @Published var knownDesks: [KnownDesk] {
        didSet {
            if let encoded = try? JSONEncoder().encode(knownDesks) {
                defaults.set(encoded, forKey: Key.knownDesks)
            }
        }
    }

    @Published var activeDeskID: UUID? {
        didSet {
            if let activeDeskID {
                defaults.set(activeDeskID.uuidString, forKey: Key.activeDeskID)
            } else {
                defaults.removeObject(forKey: Key.activeDeskID)
            }
        }
    }

    var isFirstLaunch: Bool {
        get {
            guard defaults.object(forKey: Key.hasLaunched) != nil else {
                return true
            }

            return !defaults.bool(forKey: Key.hasLaunched)
        }

        set {
            defaults.set(!newValue, forKey: Key.hasLaunched)
        }
    }

    var measurementMetric: Unit {
        isMetric ? UnitLength.centimeters : UnitLength.inches
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        DefaultsMigration.migrateIfNeeded(to: defaults)

        let initialStandingPosition = defaults.float(forKey: Key.standingPosition, defaultValue: 110)
        let initialSittingPosition = defaults.float(forKey: Key.sittingPosition, defaultValue: 70)

        standingPosition = initialStandingPosition
        sittingPosition = initialSittingPosition
        automaticStandPerHour = defaults.timeInterval(forKey: Key.automaticStandPerHour, defaultValue: 10 * 60)
        automaticStandInactivity = defaults.timeInterval(forKey: Key.automaticStandInactivity, defaultValue: 7 * 60)
        automaticStandEnabled = defaults.bool(forKey: Key.automaticStandEnabled, defaultValue: false)
        positionOffset = defaults.float(forKey: Key.positionOffset, defaultValue: 0)
        isMetric = defaults.bool(
            forKey: Key.isMetric,
            defaultValue: Locale.current.measurementSystem == .metric
        )
        doubleTapToSitStand = defaults.bool(forKey: Key.doubleTapToSitStand, defaultValue: false)
        openAtLogin = LoginItemController.isEnabled
        appLanguage = defaults.string(forKey: Key.appLanguage)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        knownDesks = defaults.knownDesks(forKey: Key.knownDesks)

        let savedActiveDeskID = defaults.string(forKey: Key.activeDeskID).flatMap(UUID.init(uuidString:))
        if let savedActiveDeskID, knownDesks.contains(where: { $0.id == savedActiveDeskID }) {
            activeDeskID = savedActiveDeskID
        } else {
            activeDeskID = knownDesks.first?.id
        }
    }

    func height(for position: Position) -> Float {
        switch position {
        case .sit:
            return sittingPosition
        case .stand:
            return standingPosition
        case .custom(let height):
            return height
        }
    }

    func rememberDesk(id: UUID, name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanedName.isEmpty ? "IDASEN Desk" : cleanedName

        if let index = knownDesks.firstIndex(where: { $0.id == id }) {
            if knownDesks[index].name.isEmpty || knownDesks[index].name == "IDASEN Desk" {
                knownDesks[index].name = displayName
            }

            knownDesks[index].lastSeen = Date()
        } else {
            knownDesks.append(KnownDesk(id: id, name: displayName, lastSeen: Date()))
        }

        knownDesks.sort { first, second in
            first.lastSeen > second.lastSeen
        }

        if activeDeskID == nil {
            activeDeskID = id
        }
    }

    func renameDesk(id: UUID, name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = knownDesks.firstIndex(where: { $0.id == id }),
              !cleanedName.isEmpty else {
            return
        }

        knownDesks[index].name = cleanedName
    }

    func forgetDesk(id: UUID) {
        knownDesks.removeAll { $0.id == id }

        if activeDeskID == id {
            activeDeskID = knownDesks.first?.id
        }
    }
}

private extension UserDefaults {
    func float(forKey key: String, defaultValue: Float) -> Float {
        guard object(forKey: key) != nil else {
            return defaultValue
        }

        return float(forKey: key)
    }

    func timeInterval(forKey key: String, defaultValue: TimeInterval) -> TimeInterval {
        guard object(forKey: key) != nil else {
            return defaultValue
        }

        return double(forKey: key)
    }

    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else {
            return defaultValue
        }

        return bool(forKey: key)
    }

    func knownDesks(forKey key: String) -> [KnownDesk] {
        guard let data = data(forKey: key),
              let desks = try? JSONDecoder().decode([KnownDesk].self, from: data) else {
            return []
        }

        return desks
    }
}
