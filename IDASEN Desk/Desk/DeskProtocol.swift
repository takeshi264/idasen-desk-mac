import CoreBluetooth
import Foundation

/// GATT layout and wire format of the Linak DPG controller used by IKEA IDASEN desks.
///
/// Heights travel over the wire as "raw" units: tenths of a millimetre above the desk's
/// lowest position. Converting to a real-world height needs the desk's base height,
/// which lives in `DeskGeometry`.
enum DeskProtocol {
    static let controlService = CBUUID(string: "99FA0001-338A-1024-8A49-009C0215F78A")
    static let controlCharacteristic = CBUUID(string: "99FA0002-338A-1024-8A49-009C0215F78A")

    static let positionService = CBUUID(string: "99FA0020-338A-1024-8A49-009C0215F78A")
    static let positionCharacteristic = CBUUID(string: "99FA0021-338A-1024-8A49-009C0215F78A")

    /// Writing a target position here makes the controller drive to it with its own
    /// soft start and soft stop. It has to be re-sent while moving, or the desk stops.
    static let referenceInputService = CBUUID(string: "99FA0030-338A-1024-8A49-009C0215F78A")
    static let referenceInputCharacteristic = CBUUID(string: "99FA0031-338A-1024-8A49-009C0215F78A")

    static let services = [controlService, positionService, referenceInputService]

    enum Command {
        static let moveDown = Data([0x46, 0x00])
        static let moveUp = Data([0x47, 0x00])
        static let wakeUp = Data([0xFE, 0x00])
        static let stop = Data([0xFF, 0x00])
    }

    /// Full travel of the IDASEN lift columns, in raw units (65 cm).
    static let rawTravel = 0...6500

    struct PositionReport: Equatable {
        /// Tenths of a millimetre above the lowest position.
        let raw: Int
        /// Signed; positive while rising, negative while lowering, zero when still.
        let speed: Int
    }

    static func decodePosition(_ data: Data) -> PositionReport? {
        guard data.count >= 4 else {
            return nil
        }

        let bytes = [UInt8](data.prefix(4))
        let raw = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        let speed = Int16(bitPattern: UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
        return PositionReport(raw: Int(raw), speed: Int(speed))
    }

    static func encodeReference(raw: Int) -> Data {
        let value = UInt16(raw.clamped(to: rawTravel))
        return Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    /// Whether an advertisement plausibly belongs to a Linak desk.
    static func looksLikeDesk(name: String?, advertisedServices: [CBUUID]) -> Bool {
        if advertisedServices.contains(where: services.contains) {
            return true
        }

        guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else {
            return false
        }

        // IDASEN desks advertise as "Desk 1234" until renamed in the Linak app.
        return name.hasPrefix("desk ") || name == "desk" || name.contains("idasen") || name.contains("linak")
    }
}

/// Maps raw controller units to real-world heights for one desk.
struct DeskGeometry: Equatable {
    /// Real height of the desktop at the lowest position, in centimetres.
    var baseHeight: Double

    static let defaultBaseHeight = 62.0

    var range: ClosedRange<Double> {
        height(raw: DeskProtocol.rawTravel.lowerBound)...height(raw: DeskProtocol.rawTravel.upperBound)
    }

    func height(raw: Int) -> Double {
        baseHeight + Double(raw) / 100
    }

    func raw(height: Double) -> Int {
        Int(((height - baseHeight) * 100).rounded()).clamped(to: DeskProtocol.rawTravel)
    }
}

enum MovingDirection: Equatable {
    case up, down, none

    init(speed: Int) {
        self = speed > 0 ? .up : speed < 0 ? .down : .none
    }
}
