import SwiftUI

public struct ThinkingBubbleView: View {
    @State private var dotScales: [CGFloat] = [0.35, 0.35, 0.35]
    @State private var dotOpacities: [Double] = [0.4, 0.4, 0.4]

    public init() {}

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { idx in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(dotScales[idx])
                    .opacity(dotOpacities[idx])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.55)
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.18)
                ) {
                    dotScales[i] = 1.05
                    dotOpacities[i] = 0.95
                }
            }
        }
    }
}
