import XCTest
@testable import IDASENDesk

final class DeskProtocolTests: XCTestCase {
    func testDecodesPositionAndSignedSpeed() {
        // raw 0x0A28 = 2600 (26 cm above base), speed 0xFF9C = -100
        let report = DeskProtocol.decodePosition(Data([0x28, 0x0A, 0x9C, 0xFF]))
        XCTAssertEqual(report, DeskProtocol.PositionReport(raw: 2600, speed: -100))
    }

    func testRejectsShortPayload() {
        XCTAssertNil(DeskProtocol.decodePosition(Data([0x01, 0x02])))
    }

    func testEncodesReferenceLittleEndianAndClamps() {
        XCTAssertEqual(DeskProtocol.encodeReference(raw: 4800), Data([0xC0, 0x12]))
        XCTAssertEqual(DeskProtocol.encodeReference(raw: -5), Data([0x00, 0x00]))
        XCTAssertEqual(DeskProtocol.encodeReference(raw: 9000), DeskProtocol.encodeReference(raw: 6500))
    }

    func testRecognisesDesksByNameOrService() {
        XCTAssertTrue(DeskProtocol.looksLikeDesk(name: "Desk 4754", advertisedServices: []))
        XCTAssertTrue(DeskProtocol.looksLikeDesk(name: "Office", advertisedServices: [DeskProtocol.controlService]))
        XCTAssertFalse(DeskProtocol.looksLikeDesk(name: "DESKTOP-7F3K", advertisedServices: []))
        XCTAssertFalse(DeskProtocol.looksLikeDesk(name: nil, advertisedServices: []))
    }

    func testGeometryRoundTrips() {
        let geometry = DeskGeometry(baseHeight: 62)
        XCTAssertEqual(geometry.height(raw: 4800), 110, accuracy: 0.001)
        XCTAssertEqual(geometry.raw(height: 110), 4800)
        XCTAssertEqual(geometry.raw(height: 10), 0)
        XCTAssertEqual(geometry.range.upperBound, 127, accuracy: 0.001)
    }

    @MainActor
    func testCalibrationKeepsPresetsAtSamePhysicalPosition() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.deskBaseHeight = 62
        preferences.sittingHeight = 72
        let sittingRaw = preferences.geometry.raw(height: preferences.sittingHeight)

        // Tape measure says the desk is 1.5 cm taller than the app thinks.
        preferences.calibrate(measuredHeight: 85.5, currentRaw: 2200)

        XCTAssertEqual(preferences.deskBaseHeight, 63.5, accuracy: 0.001)
        XCTAssertEqual(preferences.sittingHeight, 73.5, accuracy: 0.001)
        XCTAssertEqual(preferences.geometry.raw(height: preferences.sittingHeight), sittingRaw)
    }

    @MainActor
    func testLegacySettingsKeepTheirBaseHeight() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set(Float(110), forKey: "standingPositionValue")
        defaults.set(Float(70), forKey: "sittingPositionValue")

        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.deskBaseHeight, 61.5, accuracy: 0.001)
        XCTAssertEqual(preferences.sittingHeight, 70, accuracy: 0.001)
    }

    func testAppleScriptHeightParsing() {
        XCTAssertEqual(MoveDeskToHeightCommand.parse("110cm", isMetric: false), 110)
        XCTAssertEqual(MoveDeskToHeightCommand.parse("40 in", isMetric: true)!, 101.6, accuracy: 0.001)
        XCTAssertEqual(MoveDeskToHeightCommand.parse("100", isMetric: true), 100)
        XCTAssertEqual(MoveDeskToHeightCommand.parse("40", isMetric: false)!, 101.6, accuracy: 0.001)
        XCTAssertNil(MoveDeskToHeightCommand.parse("tall", isMetric: true))
    }
}
