import AppKit
import SwiftUI

/// The desk's full travel as a vertical slider. Presets are labelled stops; the knob
/// is the desktop. Drag the knob (or anywhere on the track) to pick a height, and the
/// desk drives there on release. Labels are buttons that go straight to their stop.
struct HeightRail: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences
    @Environment(\.colorScheme) private var colorScheme

    @Binding var dragTarget: Double?
    @State private var snappedStop: PresetID?

    private let inset: CGFloat = 12
    private let trackWidth: CGFloat = 6
    /// Within this distance a drag snaps to a preset.
    private let snapDistance = 1.2

    var body: some View {
        GeometryReader { proxy in
            let layout = RailLayout(range: desk.geometry.range, height: proxy.size.height, inset: inset)
            let trackX = proxy.size.width - 22

            ZStack(alignment: .topLeading) {
                track(layout: layout, x: trackX)
                stopLabels(layout: layout, trackX: trackX)

                if let target = dragTarget ?? desk.targetHeight {
                    knob(filled: false)
                        .position(x: trackX, y: layout.y(for: target))
                }

                if let height = desk.height {
                    knob(filled: true)
                        .position(x: trackX, y: layout.y(for: height))
                        .animation(.snappy(duration: 0.15), value: height)
                }

                // Generous hit area around the track for dragging.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 44, height: proxy.size.height)
                    .position(x: trackX, y: proxy.size.height / 2)
                    .gesture(dragGesture(layout: layout))
                    .onHover { inside in
                        if inside {
                            NSCursor.openHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Desk height"))
    }

    // MARK: - Parts

    private func track(layout: RailLayout, x: CGFloat) -> some View {
        let top = layout.y(for: layout.range.upperBound)
        let bottom = layout.y(for: layout.range.lowerBound)

        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(.quaternary)
                .frame(width: trackWidth, height: bottom - top)
                .position(x: x, y: (top + bottom) / 2)

            if let height = desk.height {
                let y = layout.y(for: height)
                Capsule()
                    .fill(.tint)
                    .frame(width: trackWidth, height: max(trackWidth, bottom - y))
                    .position(x: x, y: (y + bottom) / 2)
                    .animation(.snappy(duration: 0.15), value: height)
            }

            ForEach(preferences.railStops) { stop in
                Circle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 4, height: 4)
                    .position(x: x, y: layout.y(for: stop.height))
            }
        }
    }

    private func stopLabels(layout: RailLayout, trackX: CGFloat) -> some View {
        let stops = preferences.railStops
        let positions = layout.labelPositions(for: stops.map(\.height), minimumSpacing: 19)
        let unit = HeightUnit(isMetric: preferences.isMetric)

        return ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
            StopLabel(
                name: stop.name,
                value: unit.label(stop.height),
                isCurrent: desk.currentPreset == stop.id,
                isTarget: desk.target == .preset(stop.id) || snappedStop == stop.id,
                number: index + 1
            ) {
                desk.moveOrStop(stop.id)
            }
            .frame(width: trackX - 20, alignment: .trailing)
            .position(x: (trackX - 20) / 2, y: positions[index])
        }
    }

    private func knob(filled: Bool) -> some View {
        Capsule()
            .fill(filled ? AnyShapeStyle(knobColor) : AnyShapeStyle(Color.clear))
            .overlay {
                Capsule()
                    .strokeBorder(filled ? AnyShapeStyle(Color.black.opacity(0.12)) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: filled ? 0.5 : 1.5, dash: filled ? [] : [3, 2]))
            }
            .frame(width: 34, height: 10)
            .shadow(color: .black.opacity(filled ? 0.25 : 0), radius: 1.5, y: 1)
            .allowsHitTesting(false)
    }

    private var knobColor: Color {
        colorScheme == .dark ? Color(white: 0.88) : .white
    }

    // MARK: - Dragging

    private func dragGesture(layout: RailLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let raw = layout.height(for: value.location.y)
                let nearest = preferences.railStops.min { abs($0.height - raw) < abs($1.height - raw) }

                if let nearest, abs(nearest.height - raw) <= snapDistance {
                    if snappedStop != nearest.id {
                        Haptics.perform(.alignment)
                    }
                    snappedStop = nearest.id
                    dragTarget = nearest.height
                } else {
                    snappedStop = nil
                    dragTarget = (raw * 2).rounded() / 2
                }
            }
            .onEnded { _ in
                defer {
                    dragTarget = nil
                    snappedStop = nil
                }

                guard let target = dragTarget else {
                    return
                }

                if let current = desk.height, abs(current - target) < 0.3 {
                    return
                }

                if let snappedStop {
                    desk.move(to: snappedStop)
                } else {
                    desk.move(toHeight: target)
                }
            }
    }
}

private struct StopLabel: View {
    let name: String
    let value: String
    let isCurrent: Bool
    let isTarget: Bool
    let number: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: name)
                    .font(.callout.weight(isCurrent || isTarget ? .semibold : .regular))
                    .foregroundStyle(isCurrent || isTarget ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .truncationMode(.tail)
                Text(verbatim: value)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text("Go to \(name) (\(number))"))
    }
}

/// Maps heights to vertical positions on the rail.
struct RailLayout {
    let range: ClosedRange<Double>
    let height: CGFloat
    let inset: CGFloat

    func y(for value: Double) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return inset + (1 - CGFloat(fraction.clamped(to: 0...1))) * (height - inset * 2)
    }

    func height(for y: CGFloat) -> Double {
        let fraction = 1 - Double((y - inset) / (height - inset * 2))
        return range.lowerBound + fraction.clamped(to: 0...1) * (range.upperBound - range.lowerBound)
    }

    /// Label centres at their stop, pushed apart where presets are close together.
    func labelPositions(for heights: [Double], minimumSpacing: CGFloat) -> [CGFloat] {
        let order = heights.indices.sorted { heights[$0] > heights[$1] }
        var positions = heights.map { y(for: $0) }

        var previous: CGFloat?
        for index in order {
            if let previous, positions[index] - previous < minimumSpacing {
                positions[index] = previous + minimumSpacing
            }
            previous = positions[index]
        }

        // If pushing down ran off the bottom, shift the whole stack back up.
        if let lowest = order.last {
            let overflow = positions[lowest] - (height - minimumSpacing / 2)
            if overflow > 0 {
                for index in order {
                    positions[index] -= overflow
                }
            }
        }

        return positions
    }
}
