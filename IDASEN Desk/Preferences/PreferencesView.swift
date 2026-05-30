import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: DeskAppModel
    @ObservedObject var preferences: Preferences

    @State private var selectedSection: PreferenceSection = .heights
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 0) {
            PreferencesSidebar(
                selectedSection: $selectedSection,
                statusTitle: model.statusTitle,
                statusColor: model.statusColor,
                liveHeight: currentDisplayedHeight,
                unit: unit
            )
            .frame(width: 188)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(section: selectedSection)

                    switch selectedSection {
                    case .desks:
                        DeskManagementContent(model: model, preferences: preferences)
                    case .heights:
                        HeightsSettingsContent(
                            model: model,
                            preferences: preferences,
                            unit: unit,
                            heightRange: heightRange,
                            currentDisplayedHeight: currentDisplayedHeight,
                            currentStoredHeight: currentStoredHeight,
                            liveHeightDetail: liveHeightDetail,
                            roundedStoredHeight: roundedStoredHeight(_:)
                        )
                    case .health:
                        HealthSettingsContent()
                    case .rhythm:
                        RhythmSettingsContent(
                            preferences: preferences,
                            canPreviewPrompt: model.isConnected
                        )
                    case .gestures:
                        GesturesSettingsContent(preferences: preferences)
                    case .app:
                        AppSettingsContent(preferences: preferences)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                hasAppeared = true
            }
        }
        .opacity(hasAppeared ? 1 : 0)
    }

    private var unit: String {
        preferences.isMetric ? "cm" : "in"
    }

    private var heightRange: ClosedRange<Double> {
        preferences.isMetric ? 60...130 : 24...51
    }

    private var currentStoredHeight: Float? {
        guard let deskPosition = model.deskPosition else {
            return nil
        }

        return deskPosition + preferences.positionOffset
    }

    private var currentDisplayedHeight: Double? {
        guard let currentStoredHeight else {
            return nil
        }

        return displayLiveHeight(currentStoredHeight)
    }

    private var liveHeightDetail: String {
        guard let currentDisplayedHeight else {
            return AppStrings.localized("Waiting for desk position")
        }

        let sitting = Double(displayHeight(preferences.sittingPosition))
        let standing = Double(displayHeight(preferences.standingPosition))
        let sittingDelta = currentDisplayedHeight - sitting
        let standingDelta = currentDisplayedHeight - standing

        if abs(sittingDelta) <= 0.15 {
            return AppStrings.localized("Aligned with sitting preset")
        }

        if abs(standingDelta) <= 0.15 {
            return AppStrings.localized("Aligned with standing preset")
        }

        let nearestTitle = AppStrings.localized(abs(sittingDelta) < abs(standingDelta) ? "Sitting" : "Standing")
        let nearestDelta = abs(sittingDelta) < abs(standingDelta) ? sittingDelta : standingDelta
        let amount = abs(nearestDelta).formatted(.number.precision(.fractionLength(1)))
        return AppStrings.format(
            nearestDelta > 0 ? "Height above %@ %@ %@" : "Height below %@ %@ %@",
            amount,
            unit,
            nearestTitle
        )
    }

    private func displayHeight(_ centimeters: Float) -> Float {
        preferences.isMetric ? centimeters : centimeters.convertToInches()
    }

    private func storedHeight(_ displayedHeight: Float) -> Float {
        preferences.isMetric ? displayedHeight : displayedHeight.convertToCentimeters()
    }

    private func roundedDisplayHeight(_ value: Double) -> Double {
        HeightDisplay.roundedDisplayHeight(value)
    }

    private func roundedStoredHeight(_ centimeters: Float) -> Float {
        let displayed = roundedDisplayHeight(Double(displayHeight(centimeters)))
        return storedHeight(Float(displayed))
    }

    private func displayLiveHeight(_ centimeters: Float) -> Double {
        let snappedHeight = HeightDisplay.snappedStoredHeight(
            centimeters,
            sitting: preferences.sittingPosition,
            standing: preferences.standingPosition
        )

        return roundedDisplayHeight(Double(displayHeight(snappedHeight)))
    }
}

private enum PreferenceSection: String, CaseIterable, Identifiable {
    case heights
    case rhythm
    case gestures
    case health
    case desks
    case app

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .desks:
            return "Devices"
        case .heights:
            return "Heights"
        case .health:
            return "Health"
        case .rhythm:
            return "Rhythm"
        case .gestures:
            return "Gestures"
        case .app:
            return "App"
        }
    }

    var subtitle: String {
        switch self {
        case .desks:
            return "Desk management"
        case .heights:
            return "Live desk and presets"
        case .health:
            return "Work and posture stats"
        case .rhythm:
            return "Standing nudges"
        case .gestures:
            return "Handle shortcuts"
        case .app:
            return "Startup and defaults"
        }
    }

    var systemImage: String {
        switch self {
        case .desks:
            return "rectangle.connected.to.line.below"
        case .heights:
            return "arrow.up.and.down"
        case .health:
            return "chart.bar.xaxis"
        case .rhythm:
            return "figure.stand"
        case .gestures:
            return "hand.tap"
        case .app:
            return "macwindow"
        }
    }
}

private struct PreferencesSidebar: View {
    @Binding var selectedSection: PreferenceSection
    let statusTitle: String
    let statusColor: Color
    let liveHeight: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AppGlyph(statusColor: statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Desk")
                        .font(.headline)
                    Text(LocalizedStringKey(statusTitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 20)

            VStack(spacing: 6) {
                ForEach(PreferenceSection.allCases) { section in
                    SidebarButton(
                        section: section,
                        isSelected: selectedSection == section
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedSection = section
                        }
                    }
                }
            }

            Spacer()

            LiveHeightTile(liveHeight: liveHeight, unit: unit)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .background(.bar)
    }
}

private struct AppGlyph: View {
    let statusColor: Color

    var body: some View {
        AppLogoMark(statusColor: statusColor)
    }
}

private struct SidebarButton: View {
    let section: PreferenceSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(section.title))
                        .font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(section.subtitle))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.34) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct LiveHeightTile: View {
    let liveHeight: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live height")
                .font(.caption)
                .foregroundStyle(.secondary)

            HeightValueReadout(
                value: liveHeight?.formatted(.number.precision(.fractionLength(1))) ?? "--",
                unit: unit,
                valueSize: 26,
                unitSize: 12
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        }
    }
}

private struct SectionHeader: View {
    let section: PreferenceSection

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(section.title))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(LocalizedStringKey(section.subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct DeskManagementContent: View {
    @ObservedObject var model: DeskAppModel
    @ObservedObject var preferences: Preferences
    @State private var renamingDesk: KnownDesk?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: model.isScanningForDesks ? "dot.radiowaves.left.and.right" : "rectangle.connected.to.line.below")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isScanningForDesks ? "Discovery is running" : "Desk discovery")
                            .font(.headline)
                        Text(model.isConnected ? "Scanning stays off until you ask for another desk." : "Find a nearby IDASEN desk and save it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .layoutPriority(0)

                    Spacer()

                    DiscoveryToggleButton(isScanning: model.isScanningForDesks) {
                        model.isScanningForDesks ? model.stopDeskDiscovery() : model.startDeskDiscovery()
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                }
            }

            if model.connectedDesks.isEmpty && preferences.knownDesks.isEmpty {
                SetupEmptyState(startDiscovery: model.startDeskDiscovery)
            }

            if !model.connectedDesks.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        DeskListHeader(title: "Connected", detail: "\(model.connectedDesks.count) active session\(model.connectedDesks.count == 1 ? "" : "s")")

                        ForEach(model.connectedDesks) { desk in
                            ManagedDeskRow(
                                title: desk.name,
                                subtitle: desk.height.map { "\($0.formatted(.number.precision(.fractionLength(1)))) cm" } ?? "Reading height",
                                badge: desk.isActive ? "Active" : "Connected",
                                systemImage: desk.isActive ? "checkmark.circle.fill" : "circle",
                                tint: desk.isActive ? .green : .secondary
                            ) {
                                if !desk.isActive {
                                    Button("Use") {
                                        model.makeActiveDesk(id: desk.id)
                                    }
                                }

                                Button("Disconnect") {
                                    model.disconnectDesk(id: desk.id)
                                }
                            }
                        }
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    DeskListHeader(title: "Nearby", detail: model.isScanningForDesks ? "Scanning for 20 seconds" : "Start discovery when you need it")

                    let availableDesks = model.discoveredDesks.filter { !$0.isConnected }

                    if availableDesks.isEmpty {
                        EmptyDeskRow(
                            title: model.isScanningForDesks ? "Searching nearby" : "No active scan",
                            detail: model.isScanningForDesks ? "New desks will appear here." : "Use Find Desk when adding another desk."
                        )
                    } else {
                        ForEach(availableDesks) { desk in
                            ManagedDeskRow(
                                title: desk.name,
                                subtitle: "Signal \(desk.rssi) dBm",
                                badge: "Nearby",
                                systemImage: "antenna.radiowaves.left.and.right",
                                tint: .accentColor
                            ) {
                                Button("Connect") {
                                    model.connectToDesk(id: desk.id)
                                }
                            }
                        }
                    }
                }
            }

            if !preferences.knownDesks.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        DeskListHeader(title: "Saved", detail: "Reconnects without scanning when possible")

                        ForEach(preferences.knownDesks) { desk in
                            let isConnected = model.connectedDesks.contains { $0.id == desk.id }
                            let isPrimary = preferences.activeDeskID == desk.id

                            ManagedDeskRow(
                                title: desk.name,
                                subtitle: "Last seen \(desk.lastSeen.formatted(date: .abbreviated, time: .shortened))",
                                badge: isPrimary ? "Primary" : (isConnected ? "Connected" : "Saved"),
                                systemImage: isPrimary ? "star.fill" : (isConnected ? "link" : "bookmark"),
                                tint: isPrimary ? .yellow : (isConnected ? .green : .secondary)
                            ) {
                                if isConnected {
                                    Button("Use") {
                                        model.makeActiveDesk(id: desk.id)
                                    }
                                } else {
                                    Button("Connect") {
                                        model.connectToDesk(id: desk.id)
                                    }
                                }

                                Button("Rename") {
                                    renamingDesk = desk
                                }

                                Button("Forget") {
                                    model.forgetDesk(id: desk.id)
                                }
                            }
                        }
                    }
                }
            }

            DeskConnectionOverview(
                connectedCount: model.connectedDesks.count,
                savedCount: preferences.knownDesks.count,
                nearbyCount: model.discoveredDesks.filter { !$0.isConnected }.count,
                isScanning: model.isScanningForDesks
            )
        }
        .sheet(item: $renamingDesk) { desk in
            RenameDeskSheet(
                initialName: desk.name,
                cancel: {
                    renamingDesk = nil
                },
                save: { name in
                    preferences.renameDesk(id: desk.id, name: name)
                    renamingDesk = nil
                }
            )
        }
    }
}

private struct DeskConnectionOverview: View {
    let connectedCount: Int
    let savedCount: Int
    let nearbyCount: Int
    let isScanning: Bool

    var body: some View {
        HStack(spacing: 12) {
            DeskOverviewTile(
                title: "Connected",
                value: "\(connectedCount)",
                detail: connectedCount == 1 ? "desk online" : "desks online",
                systemImage: "link",
                tint: .green
            )

            DeskOverviewTile(
                title: "Saved",
                value: "\(savedCount)",
                detail: "remembered",
                systemImage: "bookmark",
                tint: .accentColor
            )

            DeskOverviewTile(
                title: "Nearby",
                value: isScanning ? "\(nearbyCount)" : "--",
                detail: isScanning ? "found nearby" : "scan paused",
                systemImage: isScanning ? "antenna.radiowaves.left.and.right" : "pause",
                tint: isScanning ? .orange : .secondary
            )
        }
    }
}

private struct DeskOverviewTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.16))
        }
    }
}

private struct RenameDeskSheet: View {
    let initialName: String
    let cancel: () -> Void
    let save: (String) -> Void

    @State private var name: String
    @FocusState private var isFocused: Bool

    init(initialName: String, cancel: @escaping () -> Void, save: @escaping (String) -> Void) {
        self.initialName = initialName
        self.cancel = cancel
        self.save = save
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "text.cursor")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename desk")
                        .font(.headline)
                    Text("Use a name that makes switching obvious.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Desk name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commit)

            HStack {
                Spacer()

                Button("Cancel", action: cancel)

                Button("Save", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
        .onAppear {
            isFocused = true
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        guard !trimmedName.isEmpty else {
            return
        }

        save(trimmedName)
    }
}

private struct SetupEmptyState: View {
    let startDiscovery: () -> Void

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start with one desk")
                            .font(.title3.weight(.semibold))
                        Text("Discovery is manual, so the app does not keep scanning once a desk is connected.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    SetupGuideRow(title: "Wake the desk", detail: "Tap the handle so Bluetooth is awake.", systemImage: "hand.tap")
                    SetupGuideRow(title: "Find once", detail: "Discovery runs only when you ask.", systemImage: "dot.radiowaves.left.and.right")
                    SetupGuideRow(title: "Choose primary", detail: "Saved desks reconnect by priority.", systemImage: "star")
                }

                DiscoveryPillButton(title: "Find My Desk", systemImage: "plus", fillsWidth: true) {
                    startDiscovery()
                }
            }
        }
    }
}

private struct DiscoveryToggleButton: View {
    let isScanning: Bool
    let action: () -> Void

    var body: some View {
        if isScanning {
            HStack(spacing: 8) {
                DiscoveryStatusPill(title: "Scanning", systemImage: "dot.radiowaves.left.and.right")

                DiscoveryPillButton(title: "Stop", systemImage: "stop.fill", tint: .orange) {
                    action()
                }
                .frame(minWidth: 112)
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            DiscoveryPillButton(title: "Find Desk", systemImage: "plus") {
                action()
            }
            .frame(minWidth: 116)
        }
    }
}

private struct DiscoveryStatusPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 13)
        .frame(minWidth: 132, minHeight: 34)
        .background {
            Capsule()
                .fill(Color.accentColor.opacity(0.12))
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
        .accessibilityLabel(Text(LocalizedStringKey(title)))
    }
}

private struct DiscoveryPillButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var filled = true
    var fillsWidth = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(filled ? Color.white : tint)
        .padding(.horizontal, 18)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 34)
        .background {
            Capsule()
                .fill(filled ? tint : tint.opacity(isPressed ? 0.20 : 0.12))
        }
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(filled ? 0 : 0.34), lineWidth: 1)
        }
        .shadow(color: filled ? tint.opacity(isPressed ? 0.10 : 0.18) : .clear, radius: isPressed ? 3 : 8, y: isPressed ? 1 : 3)
        .scaleEffect(isPressed ? 0.985 : 1)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else {
                        return
                    }

                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                    action()
                }
        )
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isPressed)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            action()
        }
    }
}

private struct SetupGuideRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
            Text(LocalizedStringKey(detail))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeskListHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.headline)
            Spacer()
            Text(LocalizedStringKey(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ManagedDeskRow<Actions: View>: View {
    let title: String
    let subtitle: String
    let badge: String
    let systemImage: String
    let tint: Color
    let actions: Actions

    init(
        title: String,
        subtitle: String,
        badge: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.systemImage = systemImage
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(title))
                        .font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(badge))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                actions
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyDeskRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HeightsSettingsContent: View {
    @ObservedObject var model: DeskAppModel
    @ObservedObject var preferences: Preferences

    let unit: String
    let heightRange: ClosedRange<Double>
    let currentDisplayedHeight: Double?
    let currentStoredHeight: Float?
    let liveHeightDetail: String
    let roundedStoredHeight: (Float) -> Float

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                HStack(alignment: .top, spacing: 18) {
                    DeskHeightPreview(
                        currentHeight: currentDisplayedHeight,
                        sittingHeight: Double(displayHeight(preferences.sittingPosition)),
                        standingHeight: Double(displayHeight(preferences.standingPosition)),
                        unit: unit,
                        range: heightRange
                    )
                    .frame(width: 230, height: 180)

                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Units", selection: metricBinding) {
                            Text("cm").tag(true)
                            Text("in").tag(false)
                        }
                        .pickerStyle(.segmented)

                        LiveHeightRow(
                            value: currentDisplayedHeight,
                            unit: unit,
                            detail: liveHeightDetail
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            PresetFitCard(
                sittingHeight: Double(displayHeight(preferences.sittingPosition)),
                standingHeight: Double(displayHeight(preferences.standingPosition)),
                minimumGap: minimumPresetGap,
                unit: unit
            )

            HStack(alignment: .top, spacing: 14) {
                HeightPresetCard(
                    title: "Sitting",
                    systemImage: "chair",
                    value: sittingValue,
                    unit: unit,
                    range: sittingRange,
                    tint: .blue,
                    currentHeight: currentDisplayedHeight,
                    canMove: model.isConnected,
                    useCurrent: {
                        if let currentStoredHeight {
                            preferences.sittingPosition = storedDisplayHeight(
                                Double(displayHeight(roundedStoredHeight(currentStoredHeight))).clamped(to: sittingRange)
                            )
                        }
                    },
                    move: {
                        model.moveToSitOrStop()
                    }
                )

                HeightPresetCard(
                    title: "Standing",
                    systemImage: "figure.stand",
                    value: standingValue,
                    unit: unit,
                    range: standingRange,
                    tint: .green,
                    currentHeight: currentDisplayedHeight,
                    canMove: model.isConnected,
                    useCurrent: {
                        if let currentStoredHeight {
                            preferences.standingPosition = storedDisplayHeight(
                                Double(displayHeight(roundedStoredHeight(currentStoredHeight))).clamped(to: standingRange)
                            )
                        }
                    },
                    move: {
                        model.moveToStandOrStop()
                    }
                )
            }
        }
    }

    private var minimumPresetGap: Double {
        preferences.isMetric ? 8 : 3
    }

    private var sittingRange: ClosedRange<Double> {
        let standingHeight = Double(displayHeight(preferences.standingPosition))
        let upperBound = min(heightRange.upperBound, max(heightRange.lowerBound, standingHeight - minimumPresetGap))
        return heightRange.lowerBound...upperBound
    }

    private var standingRange: ClosedRange<Double> {
        let sittingHeight = Double(displayHeight(preferences.sittingPosition))
        let lowerBound = max(heightRange.lowerBound, min(heightRange.upperBound, sittingHeight + minimumPresetGap))
        return lowerBound...heightRange.upperBound
    }

    private var sittingValue: Binding<Double> {
        Binding {
            Double(displayHeight(preferences.sittingPosition)).clamped(to: sittingRange)
        } set: { newValue in
            preferences.sittingPosition = storedDisplayHeight(newValue.clamped(to: sittingRange))
        }
    }

    private var standingValue: Binding<Double> {
        Binding {
            Double(displayHeight(preferences.standingPosition)).clamped(to: standingRange)
        } set: { newValue in
            preferences.standingPosition = storedDisplayHeight(newValue.clamped(to: standingRange))
        }
    }

    private var metricBinding: Binding<Bool> {
        Binding {
            preferences.isMetric
        } set: { newValue in
            preferences.isMetric = newValue
        }
    }

    private func displayHeight(_ centimeters: Float) -> Float {
        preferences.isMetric ? centimeters : centimeters.convertToInches()
    }

    private func storedDisplayHeight(_ displayedHeight: Double) -> Float {
        let value = Float(displayedHeight.clamped(to: heightRange))
        return preferences.isMetric ? value : value.convertToCentimeters()
    }
}

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.14))
        }
    }
}

private struct PresetFitCard: View {
    let sittingHeight: Double
    let standingHeight: Double
    let minimumGap: Double
    let unit: String

    var body: some View {
        SettingsCard {
            HStack(spacing: 14) {
                Image(systemName: isComfortable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Preset spacing")
                            .font(.headline)
                        Text(gapText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(isComfortable ? "Sitting and standing targets are separated clearly." : "Keep a clearer gap between sitting and standing targets.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    PresetMiniChip(title: "Sit", value: sittingHeight, unit: unit, color: .blue)
                    PresetMiniChip(title: "Stand", value: standingHeight, unit: unit, color: .green)
                }
            }
        }
    }

    private var gap: Double {
        standingHeight - sittingHeight
    }

    private var isComfortable: Bool {
        gap >= minimumGap
    }

    private var statusColor: Color {
        isComfortable ? .green : .orange
    }

    private var gapText: String {
        "\(gap.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}

private struct PresetMiniChip: View {
    let title: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text("\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color.opacity(0.16))
        }
    }
}

private struct DeskHeightPreview: View {
    let currentHeight: Double?
    let sittingHeight: Double
    let standingHeight: Double
    let unit: String
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let x = size.width * 0.48
            let bottom = size.height * 0.82
            let top = size.height * 0.18
            let currentY = yPosition(for: currentHeight ?? sittingHeight, top: top, bottom: bottom)
            let sittingY = yPosition(for: sittingHeight, top: top, bottom: bottom)
            let standingY = yPosition(for: standingHeight, top: top, bottom: bottom)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.14),
                                Color(nsColor: .controlBackgroundColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                PreviewGuideLine(y: standingY, title: "Stand", color: .green)
                PreviewGuideLine(y: sittingY, title: "Sit", color: .blue)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 7, height: bottom - top)
                    .position(x: x, y: (top + bottom) / 2)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: size.width * 0.56, height: 13)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .position(x: x, y: currentY)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.76))
                    .frame(width: 8, height: bottom - currentY)
                    .position(x: x - size.width * 0.20, y: (bottom + currentY) / 2)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.76))
                    .frame(width: 8, height: bottom - currentY)
                    .position(x: x + size.width * 0.20, y: (bottom + currentY) / 2)

                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 30, height: 30)
                    .position(x: x, y: currentY)

                Text(currentHeight?.formatted(.number.precision(.fractionLength(1))) ?? "--")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .position(x: size.width * 0.77, y: currentY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.spring(response: 0.45, dampingFraction: 0.76), value: currentHeight)
        }
    }

    private func yPosition(for height: Double, top: CGFloat, bottom: CGFloat) -> CGFloat {
        let progress = CGFloat(((height - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(to: 0...1))
        return bottom - (bottom - top) * progress
    }
}

private struct PreviewGuideLine: View {
    let y: CGFloat
    let title: String
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 16, y: y))
                path.addLine(to: CGPoint(x: proxy.size.width - 16, y: y))
            }
            .stroke(color.opacity(0.38), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            Text(LocalizedStringKey(title))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .position(x: 36, y: y - 10)
        }
    }
}

private struct LiveHeightRow: View {
    let value: Double?
    let unit: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeightValueReadout(
                value: value?.formatted(.number.precision(.fractionLength(1))) ?? "--",
                unit: unit,
                valueSize: 42,
                unitSize: 17
            )

            Label {
                Text(verbatim: detail)
            } icon: {
                Image(systemName: "ruler")
            }
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HeightPresetCard: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let tint: Color
    let currentHeight: Double?
    let canMove: Bool
    let useCurrent: () -> Void
    let move: () -> Void

    @State private var didCaptureCurrent = false

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(title))
                            .font(.headline)
                        DeltaPill(value: value, currentHeight: currentHeight, unit: unit)
                    }

                    Spacer()

                    HeightValueReadout(
                        value: value.formatted(.number.precision(.fractionLength(1))),
                        unit: unit,
                        valueSize: 29,
                        unitSize: 14
                    )
                }

                MagneticHeightSlider(value: $value, range: range, unit: unit, tint: tint)

                HStack(spacing: 8) {
                    Button {
                        useCurrent()
                        didCaptureCurrent = true

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                            didCaptureCurrent = false
                        }
                    } label: {
                        Label(LocalizedStringKey(didCaptureCurrent ? "Saved" : "Use Now"), systemImage: didCaptureCurrent ? "checkmark" : "target")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(currentHeight == nil)
                    .tint(didCaptureCurrent ? .green : nil)

                    Button {
                        move()
                    } label: {
                        Label("Move", systemImage: "arrow.up.and.down")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canMove)
                }
                .controlSize(.small)
            }
        }
    }
}

private struct MagneticHeightSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let tint: Color

    @State private var isDragging = false
    @State private var snappedInteger: Int?
    @State private var lastHapticInteger: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = CGFloat(normalized(value).clamped(to: 0...1))
                let knobX = max(13, min(width - 13, width * progress))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.13))
                        .frame(height: 9)
                        .position(x: width / 2, y: 24)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.55), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, knobX), height: 9)
                        .position(x: max(5, knobX / 2), y: 24)

                    TickMarks(range: range, tint: tint, snappedInteger: snappedInteger)
                        .frame(height: 38)
                        .position(x: width / 2, y: 24)

                    if let snappedInteger {
                        Text("\(snappedInteger)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.16))
                            .clipShape(Capsule())
                            .position(x: knobX, y: 2)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: isDragging ? 28 : 24, height: isDragging ? 28 : 24)
                        .overlay {
                            Circle()
                                .strokeBorder(tint, lineWidth: snappedInteger == nil ? 2 : 3)
                        }
                        .shadow(color: tint.opacity(snappedInteger == nil ? 0.16 : 0.48), radius: snappedInteger == nil ? 5 : 11)
                        .scaleEffect(snappedInteger == nil ? 1 : 1.12)
                        .position(x: knobX, y: 24)
                        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: snappedInteger)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            updateValue(locationX: gesture.location.x, width: width)
                        }
                        .onEnded { _ in
                            isDragging = false
                            lastHapticInteger = nil

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                if !isDragging {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        snappedInteger = nil
                                    }
                                }
                            }
                        }
                )
            }
            .frame(height: 46)

            HStack {
                Text(range.lowerBound.formatted(.number.precision(.fractionLength(0))))
                Spacer()
                Text(range.upperBound.formatted(.number.precision(.fractionLength(0))))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let clampedX = min(max(locationX, 0), width)
        let rawProgress = Double(clampedX / max(width, 1))
        let rawValue = range.lowerBound + rawProgress * (range.upperBound - range.lowerBound)
        let nearestInteger = rawValue.rounded()
        let threshold = unit == "cm" ? 0.90 : 0.35
        let shouldSnap = abs(rawValue - nearestInteger) <= threshold
        let nextValue = shouldSnap ? nearestInteger : rawValue

        if shouldSnap {
            let integer = Int(nearestInteger)
            snappedInteger = integer

            if lastHapticInteger != integer {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                lastHapticInteger = integer
            }
        } else {
            snappedInteger = nil
            lastHapticInteger = nil
        }

        value = nextValue.clamped(to: range)
    }

    private func normalized(_ height: Double) -> Double {
        (height - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

private struct TickMarks: View {
    let range: ClosedRange<Double>
    let tint: Color
    let snappedInteger: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let tickCount = 10

            ZStack(alignment: .leading) {
                ForEach(0...tickCount, id: \.self) { index in
                    let ratio = CGFloat(index) / CGFloat(tickCount)
                    let value = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                    let rounded = Int(value.rounded())
                    let isSnapped = snappedInteger == rounded

                    Capsule()
                        .fill(isSnapped ? tint : Color.secondary.opacity(index.isMultiple(of: 5) ? 0.32 : 0.20))
                        .frame(width: isSnapped ? 3 : 1, height: isSnapped ? 26 : (index.isMultiple(of: 5) ? 18 : 12))
                        .position(x: width * ratio, y: 19)
                        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: snappedInteger)
                }
            }
        }
    }
}

private struct DeltaPill: View {
    let value: Double
    let currentHeight: Double?
    let unit: String

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: text)
    }

    private var text: String {
        guard let currentHeight else {
            return AppStrings.localized("No live height")
        }

        let delta = value - currentHeight
        guard abs(delta) > 0.15 else {
            return AppStrings.localized("Live height badge")
        }

        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(abs(delta).formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    private var color: Color {
        guard let currentHeight else {
            return .secondary
        }

        return abs(value - currentHeight) <= 0.15 ? .green : .secondary
    }
}

private struct HealthSettingsContent: View {
    @ObservedObject private var healthStats = HealthStatsStore.shared
    @State private var selectedPeriod: HealthStatsPeriod = .week
    @State private var selectedDay: Date?
    @State private var isConfirmingReset = false

    var body: some View {
        let summary = healthStats.summary(for: selectedPeriod)
        let focusedDay = selectedDay.flatMap { selectedDay in
            summary.days.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
        } ?? summary.days.last(where: \.hasActivity)

        VStack(alignment: .leading, spacing: 16) {
            HealthHeroCard(
                summary: summary,
                isTracking: healthStats.isTracking,
                selectedPeriod: $selectedPeriod
            )

            HStack(alignment: .top, spacing: 12) {
                HealthMetricTile(
                    title: "Office time",
                    value: HealthStatsSummary.formatDuration(summary.workSeconds),
                    detail: AppStrings.format(summary.activeDays == 1 ? "Active day %d" : "Active days %d", summary.activeDays),
                    systemImage: "clock",
                    tint: .accentColor
                )

                HealthMetricTile(
                    title: "Standing",
                    value: HealthStatsSummary.formatDuration(summary.standingSeconds),
                    detail: AppStrings.format("Percent of time %d", Int((summary.standingRatio * 100).rounded())),
                    systemImage: "figure.stand",
                    tint: .green
                )

                HealthMetricTile(
                    title: "Stand-ups",
                    value: "\(summary.standTransitions)",
                    detail: AppStrings.localized("Height transitions"),
                    systemImage: "arrow.up.circle",
                    tint: .orange
                )
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sit / stand balance")
                                .font(.headline)
                            Text(summary.insightText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(verbatim: AppStrings.format("Percent standing %d", Int((summary.standingRatio * 100).rounded())))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HealthBalanceBar(summary: summary)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Daily rhythm", systemImage: "chart.bar.xaxis")
                            .font(.headline)

                        Spacer()

                        Text(focusedDayDetail(focusedDay, fallback: summary))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HealthActivityChart(summary: summary, selectedDay: $selectedDay)
                        .frame(height: selectedPeriod == .week ? 190 : 170)
                }
            }

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "lock.doc")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Health data")
                            .font(.headline)
                        Text("Stats stay local on this Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label("Reset", systemImage: "trash")
                    }
                }
            }
        }
        .onChange(of: selectedPeriod) { _ in
            selectedDay = nil
        }
        .confirmationDialog("Reset health stats?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive) {
                healthStats.reset()
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    private func focusedDayDetail(_ day: HealthStatsDay?, fallback summary: HealthStatsSummary) -> String {
        guard let day, day.hasActivity else {
            return AppStrings.format("Average duration %@", HealthStatsSummary.formatDuration(summary.averageWorkdaySeconds))
        }

        let style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day()
            .locale(AppStrings.locale)
        let date = day.day.formatted(style)
        return AppStrings.format("Date duration %@ %@", date, HealthStatsSummary.formatDuration(day.workSeconds))
    }
}

private struct HealthActivityGlyph: View {
    let isTracking: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(isTracking ? 0.90 : 0.54),
                            Color.teal.opacity(isTracking ? 0.74 : 0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }

            Image(systemName: isTracking ? "figure.stand" : "heart.text.square")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .offset(y: isTracking ? -1 : 0)

            if isTracking {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 8, height: 8)
                    .offset(x: 18, y: -18)
            }
        }
        .shadow(color: Color.green.opacity(isTracking ? 0.22 : 0.08), radius: 10, y: 5)
    }
}

private struct HealthHeroCard: View {
    let summary: HealthStatsSummary
    let isTracking: Bool
    @Binding var selectedPeriod: HealthStatsPeriod

    var body: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 16) {
                HealthActivityGlyph(isTracking: isTracking)
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text("Health")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))

                        Text(isTracking ? "Live" : "Paused")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isTracking ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((isTracking ? Color.green : Color.secondary).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(summary.insightText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(summary.dateRangeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 9) {
                    HealthProgressRing(
                        ratio: summary.standingRatio,
                        target: 0.30,
                        title: "Standing",
                        emptyTitle: "No data"
                    )
                    .frame(width: 72, height: 72)

                    HealthPeriodSwitch(selection: $selectedPeriod)
                        .frame(width: 178)
                }
            }
        }
    }
}

private struct HealthProgressRing: View {
    let ratio: Double
    let target: Double
    let title: String
    let emptyTitle: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.13), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(ratio.clamped(to: 0...1)))
                .stroke(
                    AngularGradient(
                        colors: [.green, .mint, .accentColor, .green],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.46, dampingFraction: 0.82), value: ratio)
            Circle()
                .trim(from: CGFloat(target.clamped(to: 0...1)), to: CGFloat(min(target + 0.01, 1)))
                .stroke(Color.orange.opacity(0.84), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(ratio > 0 ? "\(Int((ratio * 100).rounded()))%" : "--")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(LocalizedStringKey(ratio > 0 ? title : emptyTitle))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(AppStrings.localized("30% standing target"))
    }
}

private struct HealthPeriodSwitch: View {
    @Binding var selection: HealthStatsPeriod

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HealthStatsPeriod.allCases) { period in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selection = period
                    }
                } label: {
                    Text(period.shortTitle)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selection == period ? Color.accentColor : Color.secondary)
                        .background(selection == period ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(period.title)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        }
    }
}

private struct HealthMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.18))
        }
    }
}

private struct HealthBalanceBar: View {
    let summary: HealthStatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let sittingWidth = width * CGFloat(summary.sittingRatio)
                let standingWidth = width * CGFloat(summary.standingRatio)
                let transitionRatio = summary.workSeconds > 0 ? summary.transitionSeconds / summary.workSeconds : 0
                let transitionWidth = width * CGFloat(transitionRatio)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.blue.opacity(0.72))
                        .frame(width: sittingWidth)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.45))
                        .frame(width: transitionWidth)
                    Rectangle()
                        .fill(Color.green.opacity(0.78))
                        .frame(width: standingWidth)
                    Spacer(minLength: 0)
                }
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }
            .frame(height: 14)

            HStack(spacing: 14) {
                HealthLegend(title: "Sitting", value: HealthStatsSummary.formatDuration(summary.sittingSeconds), color: .blue)
                HealthLegend(title: "Standing", value: HealthStatsSummary.formatDuration(summary.standingSeconds), color: .green)
                HealthLegend(title: "Moving", value: HealthStatsSummary.formatDuration(summary.transitionSeconds), color: .accentColor)
                Spacer()
            }
        }
    }
}

private struct HealthLegend: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

private struct HealthActivityChart: View {
    let summary: HealthStatsSummary
    @Binding var selectedDay: Date?

    var body: some View {
        GeometryReader { proxy in
            let maxWork = max(summary.days.map(\.workSeconds).max() ?? 0, 60)
            let spacing: CGFloat = summary.period == .week ? 10 : 3
            let labelHeight: CGFloat = 25
            let chartHeight = max(1, proxy.size.height - labelHeight)
            let averageY = chartHeight - chartHeight * CGFloat((summary.averageWorkdaySeconds / maxWork).clamped(to: 0...1))

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.32))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.10))
                    }
                    .frame(height: chartHeight)
                    .offset(y: -labelHeight)

                HealthChartGrid()
                .frame(height: chartHeight)
                .offset(y: -labelHeight)

                if summary.averageWorkdaySeconds > 0 {
                    Path { path in
                        path.move(to: CGPoint(x: 8, y: averageY))
                        path.addLine(to: CGPoint(x: proxy.size.width - 8, y: averageY))
                    }
                    .stroke(Color.orange.opacity(0.62), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .offset(y: -labelHeight)

                    Text(verbatim: AppStrings.format("Avg duration %@", HealthStatsSummary.formatDuration(summary.averageWorkdaySeconds)))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.78))
                        .clipShape(Capsule())
                        .position(x: min(proxy.size.width - 45, 48), y: averageY - labelHeight - 12)
                }

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(summary.days) { day in
                        HealthDayBar(
                            day: day,
                            maxWork: maxWork,
                            chartHeight: chartHeight,
                            showsCompactLabel: summary.period == .month,
                            isSelected: selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day.day) } ?? false
                        ) {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) {
                                selectedDay = day.day
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HealthChartGrid: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(1...3, id: \.self) { index in
                    let y = proxy.size.height * CGFloat(index) / 4
                    Path { path in
                        path.move(to: CGPoint(x: 8, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width - 8, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                }
            }
        }
    }
}

private struct HealthDayBar: View {
    let day: HealthStatsDay
    let maxWork: TimeInterval
    let chartHeight: CGFloat
    let showsCompactLabel: Bool
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(isSelected ? 0.18 : 0.07))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        if day.standingSeconds > 0 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.64), Color.green],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: segmentHeight(day.standingSeconds))
                        }

                        if day.transitionSeconds > 0 {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.48))
                                .frame(height: segmentHeight(day.transitionSeconds))
                        }

                        if day.sittingSeconds > 0 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.45), Color.blue.opacity(0.72)],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: segmentHeight(day.sittingSeconds))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: totalHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: day.hasActivity ? Color.black.opacity(0.08) : .clear, radius: 3, y: 1)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
                    }

                    if day.hasActivity {
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.42))
                            .frame(width: isSelected ? 6 : 4, height: isSelected ? 6 : 4)
                            .offset(y: 9)
                    }
                }

                Text(verbatim: label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor : (day.hasActivity ? .primary : .secondary))
                    .lineLimit(1)
                    .frame(height: 16)
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var totalHeight: CGFloat {
        guard day.workSeconds > 0 else {
            return 3
        }

        return max(5, chartHeight * CGFloat(day.workSeconds / maxWork))
    }

    private var label: String {
        let calendar = Calendar.current

        if showsCompactLabel {
            let dayNumber = calendar.component(.day, from: day.day)
            return dayNumber == 1 || dayNumber.isMultiple(of: 5) ? "\(dayNumber)" : ""
        }

        return day.day.formatted(.dateTime.weekday(.narrow).locale(AppStrings.locale))
    }

    private var helpText: String {
        let date = day.day.formatted(.dateTime.month(.abbreviated).day().locale(AppStrings.locale))
        let work = HealthStatsSummary.formatDuration(day.workSeconds)
        let standing = HealthStatsSummary.formatDuration(day.standingSeconds)
        return AppStrings.format("Day health help %@ %@ %@", date, work, standing)
    }

    private func segmentHeight(_ seconds: TimeInterval) -> CGFloat {
        guard day.workSeconds > 0 else {
            return 0
        }

        return max(1, totalHeight * CGFloat(seconds / day.workSeconds))
    }
}

private struct RhythmSettingsContent: View {
    @ObservedObject var preferences: Preferences
    let canPreviewPrompt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                ToggleRow(
                    title: "Standing nudges",
                    subtitle: "Prompt before moving to standing height.",
                    systemImage: "bell.badge",
                    isOn: $preferences.automaticStandEnabled
                )
            }

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "bell.and.waves.left.and.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preview reminder")
                            .font(.headline)
                        Text(canPreviewPrompt ? "Open the standing prompt now." : "Connect the desk to preview the prompt.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        DeskMotionController.shared?.autoStand.showPreviewPrompt()
                    } label: {
                        Label("Preview", systemImage: "play.fill")
                    }
                    .disabled(!canPreviewPrompt)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    RhythmPicker(
                        selectedRhythm: selectedRhythm,
                        select: applyRhythm(_:)
                    )

                    RhythmTimeline(
                        standMinutes: preferences.automaticStandPerHour / 60,
                        activityMinutes: preferences.automaticStandInactivity / 60
                    )
                }
            }

            SettingsCard {
                VStack(spacing: 14) {
                    ValueSlider(
                        title: "Standing window",
                        value: automaticStandMinutesBinding,
                        range: 5...25,
                        step: 5,
                        unit: "min / hour"
                    )

                    ValueSlider(
                        title: "Activity window",
                        value: automaticStandInactivityMinutesBinding,
                        range: 2...20,
                        step: 1,
                        unit: "min"
                    )
                }
            }
        }
    }

    private var automaticStandMinutesBinding: Binding<Double> {
        Binding {
            preferences.automaticStandPerHour / 60
        } set: { newValue in
            preferences.automaticStandPerHour = newValue * 60
        }
    }

    private var automaticStandInactivityMinutesBinding: Binding<Double> {
        Binding {
            preferences.automaticStandInactivity / 60
        } set: { newValue in
            preferences.automaticStandInactivity = newValue * 60
        }
    }

    private var selectedRhythm: AutoStandRhythm? {
        AutoStandRhythm.allCases.first { rhythm in
            abs(rhythm.standMinutes - automaticStandMinutesBinding.wrappedValue) < 0.1 &&
            abs(rhythm.activityMinutes - automaticStandInactivityMinutesBinding.wrappedValue) < 0.1
        }
    }

    private func applyRhythm(_ rhythm: AutoStandRhythm) {
        preferences.automaticStandInactivity = rhythm.activityMinutes * 60
        preferences.automaticStandPerHour = rhythm.standMinutes * 60
    }
}

private enum AutoStandRhythm: CaseIterable, Identifiable {
    case gentle
    case balanced
    case active

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .gentle:
            return "Gentle"
        case .balanced:
            return "Balanced"
        case .active:
            return "Active"
        }
    }

    var standMinutes: Double {
        switch self {
        case .gentle:
            return 5
        case .balanced:
            return 10
        case .active:
            return 15
        }
    }

    var activityMinutes: Double {
        switch self {
        case .gentle:
            return 10
        case .balanced:
            return 7
        case .active:
            return 5
        }
    }

    var systemImage: String {
        switch self {
        case .gentle:
            return "leaf"
        case .balanced:
            return "circle.lefthalf.filled"
        case .active:
            return "bolt"
        }
    }
}

private struct RhythmPicker: View {
    let selectedRhythm: AutoStandRhythm?
    let select: (AutoStandRhythm) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AutoStandRhythm.allCases) { rhythm in
                let isSelected = selectedRhythm == rhythm

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        select(rhythm)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: rhythm.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(LocalizedStringKey(rhythm.title))
                            .font(.subheadline.weight(.semibold))
                        Text("\(Int(rhythm.standMinutes)) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86)
                    .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor).opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.48) : Color.secondary.opacity(0.14))
                    }
                    .scaleEffect(isSelected ? 1.02 : 1)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(rhythm.title)
            }
        }
    }
}

private struct RhythmTimeline: View {
    let standMinutes: Double
    let activityMinutes: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Hourly rhythm", systemImage: "clock")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(standMinutes)) min stand")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let standWidth = width * CGFloat((standMinutes / 60).clamped(to: 0...1))
                let activeWidth = width * CGFloat((activityMinutes / 60).clamped(to: 0...1))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.green.opacity(0.26))
                        .frame(width: standWidth)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.38))
                        .frame(width: activeWidth)
                }
            }
            .frame(height: 14)
        }
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range, step: step)
                .tint(.accentColor)
        }
    }
}

private struct GesturesSettingsContent: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                ToggleRow(
                    title: "Double tap handle",
                    subtitle: "Trigger saved sitting and standing heights.",
                    systemImage: "hand.tap",
                    isOn: $preferences.doubleTapToSitStand
                )
            }

            SettingsCard {
                GesturePulsePreview()
                    .frame(height: 130)
            }
        }
    }
}

private struct GesturePulsePreview: View {
    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(Color.accentColor.opacity(index == 0 ? 0.42 : 0.22), lineWidth: index == 0 ? 5 : 12)
                    .frame(width: 62, height: 62)
                    .overlay {
                        Image(systemName: "hand.tap")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Double tap")
                    .font(.headline)
                Text("Two clear handle movements in the same direction.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct AppSettingsContent: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                ToggleRow(
                    title: "Open at login",
                    subtitle: "Start IDASEN Desk with macOS.",
                    systemImage: "power",
                    isOn: $preferences.openAtLogin
                )
            }

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Language")
                            .font(.headline)
                        Text("Choose the app display language.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("Language", selection: $preferences.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(LocalizedStringKey(language.displayName)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset defaults")
                            .font(.headline)
                        Text("Restore heights and standing rhythm.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset") {
                        preferences.sittingPosition = 70
                        preferences.standingPosition = 110
                        preferences.automaticStandPerHour = 10 * 60
                        preferences.automaticStandInactivity = 7 * 60
                    }
                }
            }
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                Text(LocalizedStringKey(subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
