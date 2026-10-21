import Charts
import SwiftUI

struct ActivitySettingsView: View {
    @Environment(ActivityStore.self) private var activity
    @State private var range = 7
    @State private var isConfirmingReset = false

    var body: some View {
        let today = activity.day(containing: Date())
        let days = activity.recentDays(range)
        let activeDays = days.filter { $0.trackedSeconds > 0 }

        SettingsForm {
            Section {
                HStack(spacing: 0) {
                    StatTile(value: Formatters.duration(today.standingSeconds), title: Text("Standing"))
                    Divider()
                    StatTile(value: Formatters.duration(today.sittingSeconds), title: Text("Sitting"))
                    Divider()
                    StatTile(value: today.standTransitions.formatted(), title: Text("Stand-ups"))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Today")
            }

            Section {
                Picker("Range", selection: $range) {
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ActivityChart(days: days)
                    .frame(height: 170)
                    .padding(.vertical, 4)

                LabeledContent("Average standing per day") {
                    Text(verbatim: Formatters.duration(average(activeDays.map(\.standingSeconds))))
                }
                LabeledContent("Share of time standing") {
                    Text(verbatim: standingShare(activeDays).formatted(.percent.precision(.fractionLength(0))))
                }
            } header: {
                Text("History")
            }

            Section {
                Button("Clear History…", role: .destructive) {
                    isConfirmingReset = true
                }
            } footer: {
                Text("Counts time while you're at your Mac and the desk is connected. Stays on this Mac.")
            }
        }
        .confirmationDialog("Clear all activity history?", isPresented: $isConfirmingReset) {
            Button("Clear History", role: .destructive) {
                activity.reset()
            }
        }
    }

    private func average(_ values: [TimeInterval]) -> TimeInterval {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private func standingShare(_ days: [ActivityDay]) -> Double {
        let tracked = days.reduce(0) { $0 + $1.trackedSeconds }
        return tracked > 0 ? days.reduce(0) { $0 + $1.standingSeconds } / tracked : 0
    }
}

private struct StatTile: View {
    let value: String
    let title: Text

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            title
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityChart: View {
    let days: [ActivityDay]

    private var standing: String { String(localized: "Standing") }
    private var sitting: String { String(localized: "Sitting") }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Hours", day.standingSeconds / 3600)
                )
                .foregroundStyle(by: .value("Posture", standing))

                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Hours", day.sittingSeconds / 3600)
                )
                .foregroundStyle(by: .value("Posture", sitting))
            }
        }
        .chartForegroundStyleScale([standing: Color.green, sitting: Color.secondary.opacity(0.35)])
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(verbatim: "\(hours.formatted(.number.precision(.fractionLength(0)))) h")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 10 ? 7 : 1)) {
                AxisValueLabel(format: days.count > 10 ? .dateTime.month(.defaultDigits).day() : .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
    }
}
