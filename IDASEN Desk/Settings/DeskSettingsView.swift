import SwiftUI

struct DeskSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(DeskManager.self) private var desk
    @State private var renaming: KnownDesk?
    @State private var newName = ""

    var body: some View {
        SettingsForm {
            Section {
                if preferences.knownDesks.isEmpty {
                    Text("No desks yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(preferences.knownDesks) { known in
                    HStack(spacing: 10) {
                        Image(systemName: "table.furniture")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: known.name)
                            stateText(for: known)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if desk.connectedDeskID != known.id {
                            Button("Connect") {
                                desk.connect(to: known.id)
                            }
                        }

                        Menu {
                            Button("Rename…") {
                                newName = known.name
                                renaming = known
                            }
                            Divider()
                            Button("Forget This Desk", role: .destructive) {
                                desk.forget(known.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
            } header: {
                Text("Your Desks")
            } footer: {
                Text("The app reconnects automatically. With more than one desk, it connects to whichever is in range.")
            }

            Section {
                DiscoveredDeskList(showsEmptyState: false)

                HStack {
                    if desk.isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching for desks…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") {
                            desk.stopScan()
                        }
                    } else {
                        Button("Search for Desks") {
                            desk.startScan()
                        }
                    }
                }
            } header: {
                Text("Add a Desk")
            } footer: {
                Text("Hold the Bluetooth button on the desk's control panel until the light blinks blue, then connect.")
            }
        }
        .alert("Rename Desk", isPresented: isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming {
                    preferences.renameDesk(id: renaming.id, to: newName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding {
            renaming != nil
        } set: {
            if !$0 {
                renaming = nil
            }
        }
    }

    private func stateText(for known: KnownDesk) -> Text {
        if desk.connectedDeskID == known.id {
            return desk.status == .connected ? Text("Connected") : Text("Connecting…")
        }

        let lastSeen = known.lastSeen.formatted(.relative(presentation: .named))
        return Text("Last connected \(lastSeen)")
    }
}
