import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(DeskManager.self) private var desk
    @Environment(ActivityStore.self) private var activity
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general

    var body: some View {
        VStack(spacing: 0) {
            Header(open: open)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            Group {
                if desk.status == .connected {
                    DeskPanel()
                } else {
                    ConnectionStatusView(openDeskSettings: { open(.desks) })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if desk.status == .connected || activity.day(containing: Date()).trackedSeconds > 0 {
                Divider()
                TodaySummaryRow { open(.activity) }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
        }
        .frame(width: 340)
        .background {
            // Keep ⌘, and ⌘Q working from the popover.
            Group {
                Button { open(nil) } label: { EmptyView() }.keyboardShortcut(",", modifiers: .command)
                Button { NSApp.terminate(nil) } label: { EmptyView() }.keyboardShortcut("q", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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

// MARK: - Header

private struct Header: View {
    @Environment(DeskManager.self) private var desk
    let open: (SettingsTab?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(desk.status == .connected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(verbatim: desk.deskName ?? "IDASEN Desk")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Menu {
                Button("Settings…") { open(nil) }
                Button("Desks…") { open(.desks) }
                Divider()
                Button("Quit IDASEN Desk") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More"))
        }
    }
}

// MARK: - Connected

/// A stop on the height rail: a preset the desk can drive to.
struct RailStop: Identifiable, Equatable {
    let id: PresetID
    let name: String
    let height: Double
}

extension Preferences {
    var railStops: [RailStop] {
        [
            RailStop(id: .sit, name: String(localized: "Sit"), height: sittingHeight),
            RailStop(id: .stand, name: String(localized: "Stand"), height: standingHeight)
        ] + customPresets.map { RailStop(id: .custom($0.id), name: $0.name, height: $0.height) }
    }
}

private struct DeskPanel: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences
    @FocusState private var isFocused: Bool
    @State private var dragTarget: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HeightRail(dragTarget: $dragTarget)
                .frame(width: 132, height: 222)

            VStack(alignment: .leading, spacing: 0) {
                HeightReadout(height: dragTarget ?? desk.height, isPreview: dragTarget != nil, unit: unit)
                DeskStatusLine(isDragging: dragTarget != nil)
                    .padding(.top, 2)

                ReminderProgress()
                    .padding(.top, 12)

                Spacer(minLength: 10)

                SaveHeightMenu()
                    .padding(.bottom, 8)

                PrimaryActionButton()

                HStack(spacing: 6) {
                    HoldToMoveButton(direction: .up)
                    HoldToMoveButton(direction: .down)
                    Text("Hold to adjust")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 2)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 222)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onDisappear { desk.stopJog() }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .up]) { press in
            if press.phase == .down {
                desk.startJog(press.key == .upArrow ? .up : .down)
            } else {
                desk.stopJog()
            }
            return .handled
        }
        .onKeyPress(.space) {
            desk.toggleSitStand()
            return .handled
        }
        .onKeyPress(.escape) {
            guard desk.isMoving else {
                return .ignored
            }
            desk.stop()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            let stops = preferences.railStops
            guard let number = Int(press.characters), (1...stops.count).contains(number) else {
                return .ignored
            }
            desk.moveOrStop(stops[number - 1].id)
            return .handled
        }
        .onChange(of: desk.arrivals) {
            Haptics.perform(.levelChange)
        }
    }

    private var unit: HeightUnit {
        HeightUnit(isMetric: preferences.isMetric)
    }
}

private struct HeightReadout: View {
    let height: Double?
    let isPreview: Bool
    let unit: HeightUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: height.map(unit.value) ?? "––")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: height)
                .foregroundStyle(isPreview ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))

            Text(verbatim: unit.symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

private struct DeskStatusLine: View {
    @Environment(DeskManager.self) private var desk
    @Environment(ActivityTracker.self) private var tracker
    @Environment(Preferences.self) private var preferences
    let isDragging: Bool

    var body: some View {
        Group {
            if isDragging {
                Text("Release to move")
            } else if let target = desk.target {
                Text(movingText(to: target))
            } else if desk.isJogging || desk.direction != .none {
                Text(desk.direction == .down ? "Lowering…" : "Raising…")
            } else if desk.lastMoveStalled {
                HStack(spacing: 6) {
                    Label("Stopped early", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Try Again") {
                        desk.retryLastMove()
                    }
                    .buttonStyle(.link)
                }
            } else if let posture = desk.posture {
                if tracker.posture == posture, tracker.streak >= 60 {
                    let duration = Formatters.duration(tracker.streak)
                    Text(posture == .sitting ? "Sitting · \(duration)" : "Standing · \(duration)")
                } else {
                    Text(posture == .sitting ? "Sitting" : "Standing")
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func movingText(to target: DeskManager.MoveTarget) -> LocalizedStringKey {
        let rising = (desk.targetHeight ?? 0) > (desk.height ?? 0)

        switch target {
        case .preset(let preset):
            let name = preferences.railStops.first { $0.id == preset }?.name ?? ""
            return rising ? "Rising to \(name)" : "Lowering to \(name)"
        case .height(let height):
            let label = HeightUnit(isMetric: preferences.isMetric).label(height)
            return rising ? "Rising to \(label)" : "Lowering to \(label)"
        }
    }
}

/// How close the next posture reminder is, so it never comes as a surprise.
private struct ReminderProgress: View {
    @Environment(DeskManager.self) private var desk
    @Environment(ActivityTracker.self) private var tracker
    @Environment(Preferences.self) private var preferences

    var body: some View {
        if !desk.isMoving, let posture = tracker.posture, let minutes = reminderMinutes(for: posture) {
            let total = TimeInterval(minutes * 60)
            let remaining = max(0, total - tracker.streak)

            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: min(tracker.streak / total, 1))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(remaining == 0 ? .orange : .accentColor)

                Group {
                    if remaining == 0 {
                        Text(posture == .sitting ? "Time to stand up" : "Time to sit down")
                    } else {
                        let duration = Formatters.duration(remaining)
                        Text(posture == .sitting ? "Stand reminder in \(duration)" : "Sit reminder in \(duration)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private func reminderMinutes(for posture: Posture) -> Int? {
        switch posture {
        case .sitting:
            return preferences.sitReminderEnabled ? preferences.sitReminderMinutes : nil
        case .standing:
            return preferences.standReminderEnabled ? preferences.standReminderMinutes : nil
        }
    }
}

/// Offered after a manual adjustment lands between presets: keep that height.
private struct SaveHeightMenu: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences

    var body: some View {
        if let height = desk.height, !desk.isMoving, desk.currentPreset == nil, !desk.lastMoveStalled {
            let label = HeightUnit(isMetric: preferences.isMetric).label(height)

            Menu {
                Button("Save as Sit Height") {
                    preferences.setHeight(height, for: .sit)
                }
                Button("Save as Stand Height") {
                    preferences.setHeight(height, for: .stand)
                }
                Button("Save as New Preset") {
                    let number = preferences.customPresets.count + 1
                    preferences.customPresets.append(CustomPreset(name: String(localized: "Preset \(number)"), height: height))
                }
                .disabled(preferences.customPresets.count >= Preferences.maximumCustomPresets)
            } label: {
                Label("Save \(label)", systemImage: "bookmark")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// The one thing you most likely want: stand if sitting, sit if standing, stop if moving.
private struct PrimaryActionButton: View {
    @Environment(DeskManager.self) private var desk
    @Environment(Preferences.self) private var preferences

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 18)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                Text(verbatim: detail)
                    .font(.callout)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(isStop ? 0.55 : 1))
                        if let progress = desk.moveProgress {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width * progress)
                                .animation(.linear(duration: 0.2), value: progress)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .help(Text("Press Space to switch"))
    }

    private var isStop: Bool {
        desk.isMoving
    }

    private var goesUp: Bool {
        desk.posture != .standing
    }

    private var symbol: String {
        isStop ? "stop.fill" : goesUp ? "arrow.up" : "arrow.down"
    }

    private var title: LocalizedStringKey {
        isStop ? "Stop" : goesUp ? "Stand Up" : "Sit Down"
    }

    private var detail: String {
        let unit = HeightUnit(isMetric: preferences.isMetric)

        if isStop {
            guard desk.target != nil, let seconds = desk.secondsRemaining else {
                return ""
            }
            return Duration.seconds(max(1, Int(seconds.rounded()))).formatted(.units(allowed: [.seconds], width: .narrow))
        }

        return unit.label(goesUp ? preferences.standingHeight : preferences.sittingHeight)
    }

    private func perform() {
        if isStop {
            desk.stop()
        } else {
            desk.move(to: goesUp ? .stand : .sit)
        }
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// Moves while pressed, stops on release, like the handle on the desk.
private struct HoldToMoveButton: View {
    @Environment(DeskManager.self) private var desk
    @State private var isPressed = false

    let direction: MovingDirection

    var body: some View {
        Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 34, height: 28)
            .foregroundStyle(isPressed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPressed ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.primary.opacity(0.07)))
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
            .help(direction == .up ? Text("Raise (hold ↑)") : Text("Lower (hold ↓)"))
            .accessibilityLabel(direction == .up ? Text("Raise") : Text("Lower"))
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
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

enum Haptics {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
