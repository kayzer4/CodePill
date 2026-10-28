import SwiftUI

public struct ThinkingBubbleView: View {
    @State private var phase: Double = 0.0

    public init() {}

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { idx in
                Circle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 5.5, height: 5.5)
                    .opacity(dotOpacity(for: idx))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.7))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        )
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
            ) {
                phase = 1.0
            }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let offset = Double(index) * 0.3
        let val = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.25 + 0.65 * val
    }
}
