import Foundation

/// `move "stand" | "sit" | "up" | "down" | "toggle"`
final class MoveDeskCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let command = (directParameter as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        MainActor.assumeIsolated {
            let desk = AppEnvironment.shared.desk

            switch command {
            case "stand", "to-stand":
                desk.move(to: .stand)
            case "sit", "to-sit":
                desk.move(to: .sit)
            case "toggle":
                desk.toggleSitStand()
            case "up":
                desk.nudge(.up)
            case "down":
                desk.nudge(.down)
            case "stop":
                desk.stop()
            default:
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "Unknown movement. Use stand, sit, toggle, up, down or stop."
            }
        }

        return nil
    }
}

/// `move to "110cm" | "43in" | "110"` (a bare number uses the unit chosen in Settings)
final class MoveDeskToHeightCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let text = (directParameter as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        MainActor.assumeIsolated {
            let environment = AppEnvironment.shared

            guard let height = Self.parse(text, isMetric: environment.preferences.isMetric) else {
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "Couldn't read a height from \"\(text)\". Try \"110cm\" or \"43in\"."
                return
            }

            environment.desk.move(toHeight: height)
        }

        return nil
    }

    static func parse(_ text: String, isMetric: Bool) -> Double? {
        let unit = HeightUnit(isMetric: isMetric)

        if text.hasSuffix("cm") {
            return Double(text.dropLast(2).trimmingCharacters(in: .whitespaces))
        }

        if text.hasSuffix("in") {
            return Double(text.dropLast(2).trimmingCharacters(in: .whitespaces)).map { $0 * 2.54 }
        }

        return Double(text).map(unit.centimeters(fromDisplay:))
    }
}

private let errOSAGeneralError = -2700
