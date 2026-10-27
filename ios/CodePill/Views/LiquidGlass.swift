import SwiftUI

public struct StrictCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 14
    public var isHighlighted: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Color.purple.opacity(0.6) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            )
    }
}

public extension View {
    func strictCard(cornerRadius: CGFloat = 14, isHighlighted: Bool = false) -> some View {
        modifier(StrictCardModifier(cornerRadius: cornerRadius, isHighlighted: isHighlighted))
    }

    // Retain compatibility alias
    func liquidGlass(cornerRadius: CGFloat = 14, glowColor: Color = .clear, isHighlighted: Bool = false) -> some View {
        strictCard(cornerRadius: cornerRadius, isHighlighted: isHighlighted)
    }
}

/// Strict Apple Dark Mode Background (Solid true black / Dark Gray)
public struct LiquidAmbientBackground: View {
    public init() {}

    public var body: some View {
        Color(UIColor.systemBackground)
            .ignoresSafeArea()
    }
}
