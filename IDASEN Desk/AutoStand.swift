import AppKit
import Quartz
import SwiftUI

final class AutoStand: NSObject, NSWindowDelegate {

    private let oneHour: TimeInterval = 3600
    private let snoozeInterval: TimeInterval = 10 * 60
    private let inactiveRetryInterval: TimeInterval = 60
    private var upTimer: Timer?
    private var downTimer: Timer?
    private var snoozeTimer: Timer?
    private var inactiveRetryTimer: Timer?
    private var promptWindow: NSWindow?
    private var skippedStandPromptUntil: Date?

    deinit {
        unschedule()
    }

    func unschedule() {
        upTimer?.invalidate()
        downTimer?.invalidate()
        snoozeTimer?.invalidate()
        inactiveRetryTimer?.invalidate()
        upTimer = nil
        downTimer = nil
        snoozeTimer = nil
        inactiveRetryTimer = nil
        closePrompt()
    }

    func update() {
        unschedule()

        guard Preferences.shared.automaticStandEnabled else {
            skippedStandPromptUntil = nil
            return
        }

        let now = Date()
        let nextDown = now.nextHour
        let nextUp = nextStandNudgeDate(after: now)

        upTimer = Timer(fire: nextUp, interval: oneHour, repeats: true) { [weak self] _ in
            self?.handleStandNudge()
        }
        upTimer?.tolerance = 10

        downTimer = Timer(fire: nextDown, interval: oneHour, repeats: true) { [weak self] _ in
            self?.snoozeTimer?.invalidate()
            self?.inactiveRetryTimer?.invalidate()
            self?.snoozeTimer = nil
            self?.inactiveRetryTimer = nil
            self?.skippedStandPromptUntil = nil
            self?.closePrompt()
            DeskMotionController.shared?.moveToPosition(.sit)
        }
        downTimer?.tolerance = 10

        if let upTimer {
            RunLoop.main.add(upTimer, forMode: .common)
        }

        if let downTimer {
            RunLoop.main.add(downTimer, forMode: .common)
        }
    }

    func showPreviewPrompt() {
        showStandPrompt()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === promptWindow else {
            return
        }

        promptWindow = nil
    }

    private func handleStandNudge() {
        guard Preferences.shared.automaticStandEnabled else {
            return
        }

        guard DeskMotionController.shared != nil else {
            unschedule()
            return
        }

        if let skippedStandPromptUntil, Date() < skippedStandPromptUntil {
            return
        }

        guard userIsRecentlyActive else {
            scheduleInactiveRetry()
            return
        }

        inactiveRetryTimer?.invalidate()
        inactiveRetryTimer = nil
        showStandPrompt()
    }

    private var userIsRecentlyActive: Bool {
        guard let eventType = CGEventType(rawValue: ~0) else {
            return true
        }

        let lastEvent = CGEventSource.secondsSinceLastEventType(
            CGEventSourceStateID.hidSystemState,
            eventType: eventType
        )

        return lastEvent < Preferences.shared.automaticStandInactivity
    }

    private func showStandPrompt() {
        if let promptWindow {
            NSApp.activate(ignoringOtherApps: true)
            promptWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 330),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Time to stand"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: AutoStandPromptView(
                standHeight: formattedStandHeight,
                unit: unit,
                standNow: { [weak self] in
                    self?.closePrompt()
                    DeskMotionController.shared?.moveToPosition(.stand)
                },
                snooze: { [weak self] in
                    self?.closePrompt()
                    self?.scheduleSnooze()
                },
                skip: { [weak self] in
                    self?.skippedStandPromptUntil = Date().nextHour
                    self?.closePrompt()
                }
            )
        )

        promptWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func scheduleSnooze() {
        snoozeTimer?.invalidate()
        inactiveRetryTimer?.invalidate()
        inactiveRetryTimer = nil

        let fireDate = Date().addingTimeInterval(snoozeInterval)
        let sessionEnd = Date().nextHour

        guard fireDate < sessionEnd.addingTimeInterval(-30) else {
            skippedStandPromptUntil = sessionEnd
            snoozeTimer = nil
            return
        }

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.snoozeTimer = nil
            self?.handleStandNudge()
        }
        timer.tolerance = 10
        snoozeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleInactiveRetry() {
        inactiveRetryTimer?.invalidate()

        let fireDate = Date().addingTimeInterval(inactiveRetryInterval)
        let sessionEnd = Date().nextHour

        guard fireDate < sessionEnd.addingTimeInterval(-30) else {
            inactiveRetryTimer = nil
            return
        }

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.inactiveRetryTimer = nil
            self?.handleStandNudge()
        }
        timer.tolerance = 10
        inactiveRetryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func closePrompt() {
        promptWindow?.close()
        promptWindow = nil
    }

    private func nextStandNudgeDate(after now: Date) -> Date {
        let standingWindow = Preferences.shared.automaticStandPerHour.clamped(to: 60...(oneHour - 60))
        let currentHourEnd = now.nextHour
        let currentStandStart = currentHourEnd.addingTimeInterval(-standingWindow)

        if now >= currentStandStart && now < currentHourEnd.addingTimeInterval(-30) {
            return now.addingTimeInterval(2)
        }

        if currentStandStart > now {
            return currentStandStart
        }

        return currentHourEnd.addingTimeInterval(oneHour - standingWindow)
    }

    private var unit: String {
        Preferences.shared.isMetric ? "cm" : "in"
    }

    private var formattedStandHeight: String {
        var height = Preferences.shared.standingPosition

        if !Preferences.shared.isMetric {
            height = height.convertToInches()
        }

        return height.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct AutoStandPromptView: View {
    let standHeight: String
    let unit: String
    let standNow: () -> Void
    let snooze: () -> Void
    let skip: () -> Void

    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(isPulsing ? 0.12 : 0.30), lineWidth: 8)
                        .frame(width: 58, height: 58)
                        .scaleEffect(isPulsing ? 1.10 : 0.92)
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: "figure.stand")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Time to stand")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Ready for a posture reset?")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                PromptMetric(
                    title: "Target",
                    value: "\(standHeight) \(unit)",
                    systemImage: "arrow.up"
                )

                PromptMetric(
                    title: "Snooze",
                    value: "10 min",
                    systemImage: "clock"
                )
            }

            PromptWaveView()

            HStack(spacing: 8) {
                Button {
                    skip()
                } label: {
                    Label("Skip", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    snooze()
                } label: {
                    Label("Snooze", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    standNow()
                } label: {
                    Label("Stand Now", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(22)
        .frame(width: 390, height: 330, alignment: .topLeading)
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct PromptWaveView: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<24, id: \.self) { index in
                let wave = (sin(phase + Double(index) * 0.48) + 1) / 2

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.28),
                                Color.accentColor.opacity(0.75)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: CGFloat(7 + wave * 25))
            }
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

private struct PromptMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        }
    }
}
