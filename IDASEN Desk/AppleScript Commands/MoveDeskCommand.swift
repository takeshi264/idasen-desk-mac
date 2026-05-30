import Foundation

final class MoveDeskCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {

        guard let parameter = directParameter as? String else {
            return nil
        }

        let command = parameter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch command {
        case "stand", "to-stand":
            DeskMotionController.shared?.moveToPosition(.stand)
        case "sit", "to-sit":
            DeskMotionController.shared?.moveToPosition(.sit)
        case "up":
            DeskMotionController.shared?.jog(.up)
        case "down":
            DeskMotionController.shared?.jog(.down)
        default:
            break
        }

        return nil
    }
}
