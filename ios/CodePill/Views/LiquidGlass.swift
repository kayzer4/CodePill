import SwiftUI

/// iOS 26 Liquid Glass Surface Modifier
/// Multi-layered frosted glass with specular rim lighting and ambient depth
public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat = 18
    public var isHighlighted: Bool = false
    public var tintColor: Color? = nil
    public var specularOpacity: Double = 0.22

    public func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                ZStack {
                    // Deep dark glass foundation
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.72))

                    // Ultra-thin system material for genuine glass blur
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Optional subtle tint overlay
                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.10))
                    }
                }
            )
            .overlay(
                // iOS 26 Specular rim light (bright top-left to subtle bottom-right)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: isHighlighted ? Color.accentColor : Color.white.opacity(specularOpacity), location: 0.0),
                                .init(color: isHighlighted ? Color.accentColor.opacity(0.4) : Color.white.opacity(specularOpacity * 0.4), location: 0.4),
                                .init(color: Color.clear, location: 0.8),
                                .init(color: Color.white.opacity(specularOpacity * 0.2), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHighlighted ? 1.2 : 0.8
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: isHighlighted ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.22),
                radius: isHighlighted ? 12 : 8,
                x: 0,
                y: 4
            )
    }
}

public struct StrictCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 14
    public var isHighlighted: Bool = false

    public func body(content: Content) -> some View {
        content.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isHighlighted: isHighlighted))
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 18,
        isHighlighted: Bool = false,
        tintColor: Color? = nil,
        specularOpacity: Double = 0.22
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            isHighlighted: isHighlighted,
            tintColor: tintColor,
            specularOpacity: specularOpacity
        ))
    }

    func strictCard(cornerRadius: CGFloat = 14, isHighlighted: Bool = false) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isHighlighted: isHighlighted))
    }
}

/// iOS 26 Deep Spatial Glass Background
public struct LiquidAmbientBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            // Ultra-subtle ambient glow in the dark spatial canvas
            RadialGradient(
                colors: [Color.accentColor.opacity(0.04), Color.clear],
                center: .top,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }
}
