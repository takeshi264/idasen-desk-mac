import Foundation

extension Float {
    func convertToInches() -> Float {
        let centimeterMeasurement = Measurement(value: Double(self), unit: UnitLength.centimeters)
        let inchesMeasurement = centimeterMeasurement.converted(to: UnitLength.inches)
        return Float(inchesMeasurement.value)
    }

    func convertToCentimeters() -> Float {
        let inchesMeasurement = Measurement(value: Double(self), unit: UnitLength.inches)
        let centimeterMeasurement = inchesMeasurement.converted(to: UnitLength.centimeters)
        return Float(centimeterMeasurement.value)
    }

    func rounded(toPlaces places: Int) -> Float {
        let divisor = pow(10.0, Float(places))
        return (self * divisor).rounded() / divisor
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum HeightDisplay {
    static let presetSnapToleranceCentimeters: Float = 0.25

    static func snappedStoredHeight(_ height: Float, sitting: Float, standing: Float) -> Float {
        if abs(height - sitting) <= presetSnapToleranceCentimeters {
            return sitting
        }

        if abs(height - standing) <= presetSnapToleranceCentimeters {
            return standing
        }

        return height
    }

    static func roundedDisplayHeight(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

enum AppStrings {
    static var locale: Locale {
        Preferences.shared.appLanguage.locale
    }

    static func localized(_ key: String) -> String {
        switch Preferences.shared.appLanguage {
        case .system:
            return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        case .english:
            return localized(key, languageCode: "en")
        case .japanese:
            return localized(key, languageCode: "ja")
        case .traditionalChinese:
            return localized(key, languageCode: "zh-Hant")
        }
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }

    private static func localized(_ key: String, languageCode: String) -> String {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        }

        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

extension Date {
    public var nextHour: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: self)
        let currentHour = calendar.date(from: components) ?? self
        return calendar.date(byAdding: .hour, value: 1, to: currentHour) ?? self
    }
}
