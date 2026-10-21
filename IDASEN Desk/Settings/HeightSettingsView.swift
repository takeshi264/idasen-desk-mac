import SwiftUI

struct HeightSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(DeskManager.self) private var desk
    @State private var measuredHeight: Double?
    @State private var didCalibrate = false

    var body: some View {
        SettingsForm {
            Section {
                PresetRow(preset: .sit, symbol: "chair") {
                    Text("Sit")
                }
                PresetRow(preset: .stand, symbol: "figure.stand") {
                    Text("Stand")
                }

                ForEach(preferences.customPresets) { custom in
                    PresetRow(preset: .custom(custom.id), symbol: "bookmark") {
                        TextField("Name", text: nameBinding(for: custom.id))
                            .labelsHidden()
                            .textFieldStyle(.plain)
                    }
                }

                if preferences.customPresets.count < Preferences.maximumCustomPresets {
                    Button {
                        addPreset()
                    } label: {
                        Label("Add Preset", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("The desk's own control panel has no memory buttons, so presets live in this app.")
            }

            Section {
                LabeledContent("Current height") {
                    Text(verbatim: desk.height.map(unit.label) ?? "–")
                        .monospacedDigit()
                }

                LabeledContent("Measured height") {
                    HStack(spacing: 6) {
                        TextField("Measured height", value: measuredBinding, format: .number.precision(.fractionLength(0...1)), prompt: Text(verbatim: unit.value(desk.height ?? preferences.sittingHeight)))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text(verbatim: unit.symbol)
                            .foregroundStyle(.secondary)
                        Button(didCalibrate ? "Calibrated" : "Calibrate") {
                            calibrate()
                        }
                        .disabled(measuredHeight == nil || desk.heightRaw == nil)
                    }
                }
            } header: {
                Text("Calibration")
            } footer: {
                Text("If the number differs from a tape measure, measure from the floor to the top of the desk and enter it. Presets keep their physical positions.")
            }
        }
    }

    private var unit: HeightUnit {
        HeightUnit(isMetric: preferences.isMetric)
    }

    private var measuredBinding: Binding<Double?> {
        Binding {
            measuredHeight
        } set: {
            measuredHeight = $0
            didCalibrate = false
        }
    }

    private func calibrate() {
        guard let measuredHeight, let raw = desk.heightRaw else {
            return
        }

        let centimeters = unit.centimeters(fromDisplay: measuredHeight)
        guard (40...160).contains(centimeters) else {
            return
        }

        preferences.calibrate(measuredHeight: centimeters, currentRaw: raw)
        didCalibrate = true
    }

    private func addPreset() {
        let height = desk.height ?? (preferences.sittingHeight + preferences.standingHeight) / 2
        let number = preferences.customPresets.count + 1
        preferences.customPresets.append(CustomPreset(name: String(localized: "Preset \(number)"), height: height))
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding {
            preferences.customPresets.first { $0.id == id }?.name ?? ""
        } set: { name in
            if let index = preferences.customPresets.firstIndex(where: { $0.id == id }) {
                preferences.customPresets[index].name = name
            }
        }
    }
}

private struct PresetRow<Name: View>: View {
    @Environment(Preferences.self) private var preferences
    @Environment(DeskManager.self) private var desk

    let preset: PresetID
    let symbol: String
    @ViewBuilder let name: Name

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            name
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Height", value: heightBinding, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)

            Text(verbatim: unit.symbol)
                .foregroundStyle(.secondary)

            Stepper("Height", value: heightBinding, step: unit.step)
                .labelsHidden()

            Menu {
                Button("Use Current Height") {
                    if let height = desk.height {
                        preferences.setHeight(height, for: preset)
                    }
                }
                .disabled(desk.height == nil)

                Button("Move Desk Here") {
                    desk.move(to: preset)
                }
                .disabled(!desk.isConnected)

                if case .custom(let id) = preset {
                    Divider()
                    Button("Delete Preset", role: .destructive) {
                        preferences.customPresets.removeAll { $0.id == id }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var unit: HeightUnit {
        HeightUnit(isMetric: preferences.isMetric)
    }

    private var heightBinding: Binding<Double> {
        Binding {
            let centimeters = preferences.height(for: preset) ?? 0
            return (unit.display(centimeters) * 10).rounded() / 10
        } set: { value in
            preferences.setHeight(unit.centimeters(fromDisplay: value), for: preset)
        }
    }
}
