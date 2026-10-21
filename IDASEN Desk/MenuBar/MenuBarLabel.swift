import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences

    var body: some View {
        let image = Image(nsImage: DeskGlyph.image(fraction: fraction, direction: desk.direction))

        if preferences.showHeightInMenuBar, let height = desk.height {
            Label {
                Text(verbatim: HeightUnit(isMetric: preferences.isMetric).value(height))
                    .monospacedDigit()
            } icon: {
                image
            }
            .labelStyle(.titleAndIcon)
        } else {
            image
                .accessibilityLabel(Text(verbatim: "IDASEN Desk"))
        }
    }

    /// Position within the desk's travel, or nil when disconnected.
    private var fraction: Double? {
        guard let height = desk.height else {
            return nil
        }

        let range = desk.geometry.range
        return (height - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

/// A template image of the desk seen from the front, with the top drawn at the
/// desk's real position. Dimmed when disconnected; an arrow appears while moving.
@MainActor
enum DeskGlyph {
    private static var cache = [String: NSImage]()

    static func image(fraction: Double?, direction: MovingDirection) -> NSImage {
        // Quantise so the menu bar isn't redrawn on every millimetre.
        let step = fraction.map { Int(($0.clamped(to: 0...1) * 12).rounded()) }
        let key = "\(step.map(String.init) ?? "-")\(direction)"

        if let cached = cache[key] {
            return cached
        }

        let image = draw(step: step, direction: direction)
        cache[key] = image
        return image
    }

    private static func draw(step: Int?, direction: MovingDirection) -> NSImage {
        let size = NSSize(width: 18, height: 16)

        let image = NSImage(size: size, flipped: false) { _ in
            let alpha: CGFloat = step == nil ? 0.45 : 1
            NSColor.black.withAlphaComponent(alpha).setFill()

            let fraction = CGFloat(step ?? 4) / 12
            let topY = 6.5 + fraction * 6.5

            // Desktop
            NSBezierPath(roundedRect: NSRect(x: 1, y: topY, width: 16, height: 2.2), xRadius: 1, yRadius: 1).fill()

            // Lift columns and feet
            for x in [3.6, 12.6] as [CGFloat] {
                NSBezierPath(rect: NSRect(x: x, y: 1.6, width: 1.8, height: topY - 1.6)).fill()
                NSBezierPath(roundedRect: NSRect(x: x - 2.1, y: 0.4, width: 6, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()
            }

            if direction != .none {
                let arrow = NSBezierPath()
                let midX: CGFloat = 9
                let baseY: CGFloat = max(2.2, topY - 5.4)

                if direction == .up {
                    arrow.move(to: NSPoint(x: midX - 2.4, y: baseY))
                    arrow.line(to: NSPoint(x: midX + 2.4, y: baseY))
                    arrow.line(to: NSPoint(x: midX, y: baseY + 3.4))
                } else {
                    arrow.move(to: NSPoint(x: midX - 2.4, y: baseY + 3.4))
                    arrow.line(to: NSPoint(x: midX + 2.4, y: baseY + 3.4))
                    arrow.line(to: NSPoint(x: midX, y: baseY))
                }

                arrow.close()
                arrow.fill()
            }

            return true
        }

        image.isTemplate = true
        return image
    }
}
