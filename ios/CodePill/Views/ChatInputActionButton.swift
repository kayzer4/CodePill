import SwiftUI

public struct ChatInputActionButton: View {
    public let isExecuting: Bool
    public let canSend: Bool
    public let onSend: () -> Void
    public let onCancel: () -> Void

    public init(
        isExecuting: Bool,
        canSend: Bool,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isExecuting = isExecuting
        self.canSend = canSend
        self.onSend = onSend
        self.onCancel = onCancel
    }

    public var body: some View {
        Button {
            if isExecuting {
                onCancel()
                Haptics.shared.notify(.warning)
            } else if canSend {
                onSend()
                Haptics.shared.impact(.light)
            }
        } label: {
            ZStack {
                if isExecuting {
                    // TimelineView ensures smooth 60fps frame rendering
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let spinAngle = (time.truncatingRemainder(dividingBy: 1.4)) / 1.4 * 360.0
                        let pulse = 0.8 + 0.2 * sin(time * 3.2)

                        ZStack {
                            // Soft breathing ambient glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.25 * pulse),
                                            Color.accentColor.opacity(0.05),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 6,
                                        endRadius: 20
                                    )
                                )
                                .frame(width: 40, height: 40)

                            // Subtle background track ring
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 2)
                                .frame(width: 29, height: 29)

                            // Sleek spinning gradient arc
                            Circle()
                                .trim(from: 0.08, to: 0.78)
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            Color.accentColor,
                                            Color.purple.opacity(0.85),
                                            Color.accentColor.opacity(0.15)
                                        ]),
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                                )
                                .frame(width: 29, height: 29)
                                .rotationEffect(.degrees(spinAngle))
                                .shadow(color: Color.accentColor.opacity(0.45 * pulse), radius: 3)

                            // Glass center disc
                            Circle()
                                .fill(Color(UIColor.secondarySystemBackground).opacity(0.92))
                                .frame(width: 21, height: 21)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                                )

                            // Stop icon square
                            RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                                .fill(Color.primary)
                                .frame(width: 8, height: 8)
                        }
                    }
                } else {
                    // Standard Send Arrow with soft dynamic accent glow when active
                    Circle()
                        .fill(
                            canSend
                                ? LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.88)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.secondary.opacity(0.25), Color.secondary.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(
                            color: canSend ? Color.accentColor.opacity(0.4) : Color.clear,
                            radius: 5,
                            x: 0,
                            y: 2
                        )

                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : Color.white.opacity(0.45))
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isExecuting && !canSend)
    }
}
