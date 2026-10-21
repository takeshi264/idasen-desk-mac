import Foundation

enum Formatters {
    /// "1 hr, 20 min" style, localised by the system.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Converts between stored centimetres and the unit the person chose.
struct HeightUnit: Equatable {
    let isMetric: Bool

    var symbol: String {
        isMetric ? "cm" : "in"
    }

    /// Step used by steppers and keyboard nudges.
    var step: Double {
        isMetric ? 0.5 : 0.25
    }

    func display(_ centimeters: Double) -> Double {
        isMetric ? centimeters : centimeters / 2.54
    }

    func centimeters(fromDisplay value: Double) -> Double {
        isMetric ? value : value * 2.54
    }

    /// "72.5", always one decimal; used for the live readout so digits don't jump.
    func value(_ centimeters: Double) -> String {
        display(centimeters).formatted(.number.precision(.fractionLength(1)))
    }

    /// "72 cm" or "72.5 cm"; used for presets.
    func label(_ centimeters: Double) -> String {
        let value = display(centimeters).formatted(.number.precision(.fractionLength(0...1)))
        return "\(value) \(symbol)"
    }
}
