import SwiftUI

public struct ChatInputActionButton: View {
    public let isExecuting: Bool
    public let canSend: Bool
    public let onSend: () -> Void
    public let onCancel: () -> Void

    @State private var phase: Double = 0
    @State private var ambientGlow: Bool = false

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
                    // Строгое элегантное свечение (Soft minimal monochromatic aura)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.accentColor.opacity(0.35),
                                    Color.accentColor.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: ambientGlow ? 22 : 16
                            )
                        )
                        .frame(width: 44, height: 44)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: ambientGlow
                        )

                    // 4 аккуратные орбитальные точки в стиле Claude / минимализм
                    ForEach(0..<4) { index in
                        let angle = Double(index) * 90.0 + phase
                        Circle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 3.2, height: 3.2)
                            .shadow(color: Color.accentColor.opacity(0.8), radius: 3, x: 0, y: 0)
                            .offset(
                                x: 15 * cos(angle * .pi / 180),
                                y: 15 * sin(angle * .pi / 180)
                            )
                    }

                    // Тонкая полупрозрачная окружность
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.2)
                        .frame(width: 30, height: 30)

                    // Стеклянная подложка кнопки «Стоп»
                    Circle()
                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.85))
                        .frame(width: 24, height: 24)

                    // Строгий квадрат «Стоп»
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary)
                        .frame(width: 9, height: 9)
                        .shadow(color: Color.black.opacity(0.2), radius: 1.5, x: 0, y: 0.5)
                } else {
                    // Standard Send Arrow with elegant accent glow
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
        .onAppear {
            if isExecuting {
                startAnimations()
            }
        }
        .onChange(of: isExecuting) { executing in
            if executing {
                startAnimations()
            } else {
                ambientGlow = false
            }
        }
    }

    private func startAnimations() {
        ambientGlow = true
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
            phase = 360
        }
    }
}
