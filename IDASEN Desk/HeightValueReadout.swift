import SwiftUI

struct HeightValueReadout: View {
    let value: String
    let unit: String
    let valueSize: CGFloat
    let unitSize: CGFloat

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .monospacedDigit()

            Text(unit)
                .font(.system(size: unitSize, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .baselineOffset(valueSize * 0.015)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
}
