import SwiftUI

public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat = 20
    public var glowColor: Color = Color.purple.opacity(0.12)
    public var isHighlighted: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isHighlighted ? 0.6 : 0.28), location: 0.0),
                                .init(color: .white.opacity(0.08), location: 0.4),
                                .init(color: .clear, location: 0.7),
                                .init(color: .white.opacity(0.12), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: glowColor, radius: 14, x: 0, y: 6)
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        glowColor: Color = Color.purple.opacity(0.12),
        isHighlighted: Bool = false
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            glowColor: glowColor,
            isHighlighted: isHighlighted
        ))
    }
}

/// Ambient Liquid Background View
public struct LiquidAmbientBackground: View {
    @State private var animateGlow: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .ignoresSafeArea()

            // Subtle luminous fluid orbs
            Circle()
                .fill(Color.purple.opacity(0.25))
                .frame(width: 350, height: 350)
                .blur(radius: 80)
                .offset(x: animateGlow ? -60 : 40, y: animateGlow ? -200 : -260)

            Circle()
                .fill(Color.indigo.opacity(0.2))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: animateGlow ? 120 : 60, y: animateGlow ? 180 : 250)

            Circle()
                .fill(Color.cyan.opacity(0.15))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: animateGlow ? -100 : -40, y: animateGlow ? 100 : 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                animateGlow.toggle()
            }
        }
    }
}
