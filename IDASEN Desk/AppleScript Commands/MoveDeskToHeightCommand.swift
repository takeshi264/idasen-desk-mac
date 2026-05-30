import Foundation


final class MoveDeskToHeightCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {

        guard let parameter = directParameter as? String else {
            return nil
        }

        let normalizedParameter = parameter
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let height: Float?

        if normalizedParameter.hasSuffix("cm") {
            height = Float(normalizedParameter.dropLast(2))
        } else if normalizedParameter.hasSuffix("in") {
            height = Float(normalizedParameter.dropLast(2))?.convertToCentimeters()
        } else if let value = Float(normalizedParameter) {
            height = Preferences.shared.isMetric ? value : value.convertToCentimeters()
        } else {
            height = nil
        }

        if let height = height {
            DeskMotionController.shared?.moveToHeight(height)
        }

        return nil
    }
}
