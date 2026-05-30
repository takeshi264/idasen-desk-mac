import SwiftUI

struct DeskMark: View {
    let statusColor: Color
    let direction: MovingDirection

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.22),
                            Color.green.opacity(0.18),
                            Color(nsColor: .controlBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(statusColor.opacity(0.28), lineWidth: 1)
                }

            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(statusColor)
                .offset(y: arrowOffset)

            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.6)
                }
                .offset(x: -2, y: -2)
        }
        .frame(width: 44, height: 44)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: direction)
    }

    private var systemImage: String {
        switch direction {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .none:
            return "arrow.up.and.down"
        }
    }

    private var arrowOffset: CGFloat {
        switch direction {
        case .up:
            return -2
        case .down:
            return 2
        case .none:
            return 0
        }
    }
}

struct AppLogoMark: View {
    let statusColor: Color?

    init(statusColor: Color? = nil) {
        self.statusColor = statusColor
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.78, blue: 0.64),
                            Color(red: 0.08, green: 0.62, blue: 0.92),
                            Color(red: 0.40, green: 0.43, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: Color(red: 0.08, green: 0.62, blue: 0.92).opacity(0.20), radius: 7, y: 3)

            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .frame(width: 27, height: 6)

                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.78))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.78))
                }
                .frame(width: 23, height: 16)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.50))
                    .frame(width: 25, height: 3)
            }
            .offset(y: 4)

            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.20))
                .clipShape(Circle())
                .offset(x: -2, y: -21)

            Circle()
                .fill(statusColor ?? .green)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.88), lineWidth: 1.6)
                }
                .offset(x: -2, y: -2)
        }
        .frame(width: 44, height: 44)
    }
}
