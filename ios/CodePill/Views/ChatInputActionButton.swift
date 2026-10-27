import SwiftUI

public struct ChatInputActionButton: View {
    public let isExecuting: Bool
    public let canSend: Bool
    public let onSend: () -> Void
    public let onCancel: () -> Void

    @State private var isSpinning: Bool = false

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
                    // ChatGPT / Claude style stop button with animated loader ring
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                        .frame(width: 32, height: 32)

                    Circle()
                        .trim(from: 0.0, to: 0.65)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                        .animation(
                            .linear(duration: 0.9).repeatForever(autoreverses: false),
                            value: isSpinning
                        )

                    // Rounded stop square
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary)
                        .frame(width: 11, height: 11)
                } else {
                    // Standard Send Arrow
                    Circle()
                        .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 32)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : Color.white.opacity(0.5))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isExecuting && !canSend)
        .onAppear {
            if isExecuting {
                isSpinning = true
            }
        }
        .onChange(of: isExecuting) { executing in
            withAnimation(.easeInOut(duration: 0.2)) {
                isSpinning = executing
            }
        }
    }
}
