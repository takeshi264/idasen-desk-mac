import AppIntents
import Foundation

/// Shortcuts and Siri actions. They run inside the app, launching it if needed, so
/// they wait briefly for the desk to connect before giving up.
enum DeskIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notConnected

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConnected:
            return "The desk isn't connected. Make sure it's powered and nearby."
        }
    }
}

@MainActor
private func readyDesk() async throws -> DeskManager {
    let desk = AppEnvironment.shared.desk
    guard await desk.waitUntilReady() else {
        throw DeskIntentError.notConnected
    }
    return desk
}

struct StandUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Stand Up"
    static let description = IntentDescription("Raises the desk to your standing height.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await readyDesk().move(to: .stand)
        return .result()
    }
}

struct SitDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Sit Down"
    static let description = IntentDescription("Lowers the desk to your sitting height.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await readyDesk().move(to: .sit)
        return .result()
    }
}

struct ToggleDeskIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Sit/Stand"
    static let description = IntentDescription("Switches the desk between your sitting and standing heights.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await readyDesk().toggleSitStand()
        return .result()
    }
}

struct MoveDeskToHeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Desk to Height"
    static let description = IntentDescription("Moves the desk to a height in centimetres.")

    @Parameter(title: "Height (cm)", inclusiveRange: (60, 130))
    var height: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Move desk to \(\.$height) cm")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await readyDesk().move(toHeight: height)
        return .result()
    }
}

struct GetDeskHeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Desk Height"
    static let description = IntentDescription("Returns the current desk height in centimetres.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let desk = try await readyDesk()
        guard let height = desk.height else {
            throw DeskIntentError.notConnected
        }
        return .result(value: (height * 10).rounded() / 10)
    }
}

struct DeskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StandUpIntent(),
            phrases: ["Stand up with \(.applicationName)", "Raise my desk with \(.applicationName)"],
            shortTitle: "Stand Up",
            systemImageName: "figure.stand"
        )
        AppShortcut(
            intent: SitDownIntent(),
            phrases: ["Sit down with \(.applicationName)", "Lower my desk with \(.applicationName)"],
            shortTitle: "Sit Down",
            systemImageName: "chair"
        )
        AppShortcut(
            intent: ToggleDeskIntent(),
            phrases: ["Toggle my desk with \(.applicationName)"],
            shortTitle: "Toggle Sit/Stand",
            systemImageName: "arrow.up.arrow.down"
        )
    }
}
