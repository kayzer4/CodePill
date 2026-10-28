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
                    // TimelineView ensures active 60fps frame rendering without getting blocked by state updates
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let angle = (time.truncatingRemainder(dividingBy: 2.5)) / 2.5 * 360.0
                        let pulse = 0.85 + 0.15 * sin(time * 3.0)

                        ZStack {
                            // Monochromatic soft ambient aura
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.35 * pulse),
                                            Color.accentColor.opacity(0.08),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 8,
                                        endRadius: 22
                                    )
                                )
                                .frame(width: 44, height: 44)

                            // 4 moving orbital glowing dots in Claude style
                            ForEach(0..<4) { index in
                                let itemAngle = angle + Double(index) * 90.0
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 3.2, height: 3.2)
                                    .shadow(color: Color.accentColor.opacity(0.85), radius: 3, x: 0, y: 0)
                                    .offset(
                                        x: 15 * cos(itemAngle * .pi / 180),
                                        y: 15 * sin(itemAngle * .pi / 180)
                                    )
                            }

                            // Thin guide circle
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.2)
                                .frame(width: 30, height: 30)

                            // Glass center disc
                            Circle()
                                .fill(Color(UIColor.secondarySystemBackground).opacity(0.9))
                                .frame(width: 24, height: 24)

                            // Stop icon square
                            RoundedRectangle(cornerRadius: 2.8, style: .continuous)
                                .fill(Color.primary)
                                .frame(width: 9, height: 9)
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
