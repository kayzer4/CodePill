import SwiftUI

public struct ChatInputActionButton: View {
    public let isExecuting: Bool
    public let canSend: Bool
    public let onSend: () -> Void
    public let onCancel: () -> Void

    @State private var pulseGlow: Bool = false
    @State private var ringRotation: Double = 0

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
                    // Claude & ChatGPT style pulsating glow halo
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.accentColor.opacity(0.65),
                                    Color.purple.opacity(0.35),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: pulseGlow ? 26 : 18
                            )
                        )
                        .frame(width: 44, height: 44)
                        .scaleEffect(pulseGlow ? 1.15 : 0.95)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: pulseGlow
                        )

                    // Outer rotating iridescent gradient ring
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.accentColor,
                                    Color(red: 0.7, green: 0.3, blue: 1.0),
                                    Color.cyan,
                                    Color.accentColor.opacity(0.2),
                                    Color.accentColor
                                ]),
                                center: .center
                            ),
                            lineWidth: 2.2
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(ringRotation))
                        .animation(
                            .linear(duration: 1.8).repeatForever(autoreverses: false),
                            value: ringRotation
                        )

                    // Inner stop disc with glass blur and square
                    Circle()
                        .fill(Color(UIColor.systemBackground).opacity(0.85))
                        .frame(width: 28, height: 28)

                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.primary)
                        .frame(width: 10, height: 10)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                } else {
                    // Standard Send Arrow with soft dynamic accent glow when active
                    Circle()
                        .fill(
                            canSend
                                ? LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.secondary.opacity(0.28), Color.secondary.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(
                            color: canSend ? Color.accentColor.opacity(0.45) : Color.clear,
                            radius: 6,
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
        .onAppear {
            if isExecuting {
                pulseGlow = true
                ringRotation = 360
            }
        }
        .onChange(of: isExecuting) { executing in
            if executing {
                pulseGlow = true
                ringRotation = 360
            } else {
                pulseGlow = false
                ringRotation = 0
            }
        }
    }
}
