import AppKit
import SwiftUI

/// Everything the popover shows while the desk can't be controlled yet.
struct ConnectionStatusView: View {
    @Environment(DeskManager.self) private var desk
    let openDeskSettings: () -> Void

    var body: some View {
        switch desk.status {
        case .connected:
            EmptyView()

        case .starting:
            StatusMessage(symbol: nil, title: Text("Starting Bluetooth…"))

        case .bluetoothOff:
            StatusMessage(
                symbol: "antenna.radiowaves.left.and.right.slash",
                title: Text("Bluetooth is off"),
                message: Text("Turn on Bluetooth and the desk reconnects by itself.")
            ) {
                Button("Open Bluetooth Settings") {
                    SystemSettings.open(SystemSettings.bluetooth)
                }
            }

        case .unauthorized:
            StatusMessage(
                symbol: "hand.raised.fill",
                title: Text("Bluetooth access needed"),
                message: Text("Allow IDASEN Desk under Privacy & Security → Bluetooth.")
            ) {
                Button("Open Privacy Settings") {
                    SystemSettings.open(SystemSettings.bluetoothPrivacy)
                }
            }

        case .unsupported:
            StatusMessage(
                symbol: "exclamationmark.triangle.fill",
                title: Text("Bluetooth LE isn't available"),
                message: Text("This Mac can't talk to the desk.")
            )

        case .noDesk:
            DeskSetupView()

        case .searching:
            StatusMessage(
                symbol: nil,
                title: Text("Looking for \(desk.deskName ?? "IDASEN Desk")"),
                message: Text("It connects by itself when the desk is powered and in range.")
            ) {
                Button("Desk Settings…", action: openDeskSettings)
            }

        case .connecting:
            StatusMessage(
                symbol: nil,
                title: Text("Connecting to \(desk.deskName ?? "IDASEN Desk")…"),
                message: Text("The first time, macOS may ask you to pair.")
            )
        }
    }
}

/// First-run flow: pairing mode, then pick the desk from what's nearby.
private struct DeskSetupView: View {
    @Environment(DeskManager.self) private var desk

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect your desk")
                    .font(.headline)
                Text("Hold the Bluetooth button on the desk's control panel until the light blinks blue, then choose the desk below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DiscoveredDeskList()

            HStack {
                if desk.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Search Again") {
                        desk.startScan()
                    }
                }
            }
        }
        .onAppear {
            if !desk.isScanning {
                desk.startScan()
            }
        }
    }
}

/// Nearby desks with a Connect button each. Shared by the popover and Settings.
struct DiscoveredDeskList: View {
    @Environment(DeskManager.self) private var desk
    var showsEmptyState = true

    var body: some View {
        if desk.discoveredDesks.isEmpty {
            if showsEmptyState && !desk.isScanning {
                Text("No desks found nearby.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(desk.discoveredDesks) { found in
                    HStack(spacing: 8) {
                        Image(systemName: "table.furniture")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(verbatim: found.name)
                            .lineLimit(1)
                        SignalStrength(rssi: found.rssi)
                        Spacer()
                        Button("Connect") {
                            desk.connect(to: found.id)
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.05)))
                }
            }
        }
    }
}

private struct SignalStrength: View {
    let rssi: Int

    var body: some View {
        Image(systemName: "cellularbars", variableValue: level)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(Text(verbatim: "\(rssi) dBm"))
    }

    private var level: Double {
        // -90 dBm is barely reachable, -50 dBm is right next to the Mac.
        ((Double(rssi) + 90) / 40).clamped(to: 0.1...1)
    }
}

private struct StatusMessage<Actions: View>: View {
    let symbol: String?
    let title: Text
    var message: Text?
    @ViewBuilder var actions: Actions

    init(symbol: String?, title: Text, message: Text? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    title
                        .font(.headline)
                    if let message {
                        message
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            actions
                .controlSize(.small)
                .padding(.leading, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum SystemSettings {
    static let bluetooth = "x-apple.systempreferences:com.apple.BluetoothSettings"
    static let bluetoothPrivacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
    static let notifications = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

    static func open(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
