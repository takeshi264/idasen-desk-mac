import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences
    @Environment(ActivityStore.self) private var activity
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if desk.status == .connected {
                    DeskControls()
                } else {
                    ConnectionStatusView(openDeskSettings: { open(.desks) })
                }
            }
            .padding(14)

            if desk.status == .connected || activity.day(containing: Date()).trackedSeconds > 0 {
                Divider()
                TodaySummaryRow { open(.activity) }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }

            Divider()

            VStack(spacing: 0) {
                MenuRow(title: "Settings…", shortcut: ",") {
                    open(nil)
                }
                MenuRow(title: "Quit IDASEN Desk", shortcut: "q") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .frame(width: 300)
    }

    private func open(_ tab: SettingsTab?) {
        if let tab {
            settingsTab = tab
        }
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        // Menu-bar-only apps can open Settings behind other windows.
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Connected

private struct DeskControls: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: desk.deskName ?? "IDASEN Desk")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HeightReadout(height: desk.height, unit: unit)

                    DeskStatusLine()
                }

                Spacer(minLength: 0)

                HeightGauge()
                    .frame(width: 28, height: 76)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                PresetButton(preset: .sit, name: Text("Sit"), symbol: "chair")
                PresetButton(preset: .stand, name: Text("Stand"), symbol: "figure.stand")

                ForEach(preferences.customPresets) { preset in
                    PresetButton(preset: .custom(preset.id), name: Text(verbatim: preset.name), symbol: "bookmark")
                }
            }

            HStack(spacing: 8) {
                HoldToMoveButton(direction: .down, title: Text("Lower"))
                HoldToMoveButton(direction: .up, title: Text("Raise"))
            }
        }
    }

    private var unit: HeightUnit {
        HeightUnit(isMetric: preferences.isMetric)
    }
}

private struct HeightReadout: View {
    let height: Double?
    let unit: HeightUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: height.map(unit.value) ?? "––")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: height)

            Text(verbatim: unit.symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private struct DeskStatusLine: View {
    @Environment(DeskManager.self) private var desk
    @Environment(ActivityTracker.self) private var tracker
    @Environment(Preferences.self) private var preferences

    var body: some View {
        Group {
            if let target = desk.target {
                Label { movingText(to: target) } icon: { Image(systemName: desk.direction == .down ? "arrow.down" : "arrow.up") }
            } else if desk.isJogging || desk.direction != .none {
                Label(desk.direction == .down ? "Lowering…" : "Raising…", systemImage: desk.direction == .down ? "arrow.down" : "arrow.up")
            } else if desk.lastMoveStalled {
                Label("Stopped before reaching the target", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let posture = tracker.posture, tracker.streak >= 60 {
                let duration = Formatters.duration(tracker.streak)
                Text(posture == .sitting ? "Sitting for \(duration)" : "Standing for \(duration)")
            } else {
                Text("Ready")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func movingText(to target: DeskManager.MoveTarget) -> Text {
        switch target {
        case .preset(.sit):
            return Text("Moving to Sit…")
        case .preset(.stand):
            return Text("Moving to Stand…")
        case .preset(.custom(let id)):
            let name = preferences.customPresets.first { $0.id == id }?.name ?? ""
            return Text("Moving to \(name)…")
        case .height(let height):
            return Text("Moving to \(HeightUnit(isMetric: preferences.isMetric).label(height))…")
        }
    }
}

/// The desk's travel as a vertical track with preset ticks.
private struct HeightGauge: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let trackX = proxy.size.width - 5

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 6, height: height)
                    .offset(x: trackX - 3)

                if let fraction = fraction(of: desk.height) {
                    Capsule()
                        .fill(.tint)
                        .frame(width: 6, height: max(6, height * fraction))
                        .offset(x: trackX - 3, y: height * (1 - fraction))
                        .animation(.snappy(duration: 0.2), value: fraction)
                }

                ForEach(presetHeights, id: \.self) { preset in
                    if let fraction = fraction(of: preset) {
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 7, height: 2)
                            .offset(x: trackX - 13, y: height * (1 - fraction) - 1)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var presetHeights: [Double] {
        [preferences.sittingHeight, preferences.standingHeight] + preferences.customPresets.map(\.height)
    }

    private func fraction(of value: Double?) -> Double? {
        guard let value else {
            return nil
        }

        let range = desk.geometry.range
        return ((value - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(to: 0...1)
    }
}

private struct PresetButton: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences
    @State private var isHovered = false

    let preset: PresetID
    let name: Text
    let symbol: String

    var body: some View {
        Button {
            desk.moveOrStop(preset)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isMovingHere ? "stop.fill" : symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                    .background(Circle().fill(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))

                VStack(alignment: .leading, spacing: 0) {
                    name
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(verbatim: heightLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(isHovered ? 0.09 : 0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isMovingHere ? Text("Stop") : Text("Move to this height"))
    }

    private var isMovingHere: Bool {
        desk.target == .preset(preset)
    }

    private var isHighlighted: Bool {
        isMovingHere || desk.currentPreset == preset
    }

    private var heightLabel: String {
        preferences.height(for: preset).map(HeightUnit(isMetric: preferences.isMetric).label) ?? ""
    }
}

/// Moves while pressed, stops on release, like the handle on the desk.
private struct HoldToMoveButton: View {
    @Environment(DeskManager.self) private var desk
    @State private var isPressed = false

    let direction: MovingDirection
    let title: Text

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
            title
                .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .foregroundStyle(isPressed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPressed ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.primary.opacity(0.05)))
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else {
                        return
                    }
                    isPressed = true
                    desk.startJog(direction)
                }
                .onEnded { _ in
                    isPressed = false
                    desk.stopJog()
                }
        )
        .onDisappear {
            if isPressed {
                isPressed = false
                desk.stopJog()
            }
        }
        .help(Text("Hold to move"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            desk.nudge(direction)
        }
    }
}

// MARK: - Footer

private struct TodaySummaryRow: View {
    @Environment(ActivityStore.self) private var activity
    let action: () -> Void

    var body: some View {
        let today = activity.day(containing: Date())

        MenuRowButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("Today: standing \(Formatters.duration(today.standingSeconds)) · \(today.standTransitions) stand-ups")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
    }
}

struct MenuRow: View {
    let title: LocalizedStringKey
    let shortcut: Character
    let action: () -> Void

    var body: some View {
        MenuRowButton(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "⌘\(shortcut.uppercased())")
                    .foregroundStyle(.secondary)
            }
        }
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
    }
}

/// A button styled like a menu item, with the hover highlight macOS menus use.
struct MenuRowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isHovered ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
