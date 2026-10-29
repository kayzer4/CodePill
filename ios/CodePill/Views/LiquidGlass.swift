import SwiftUI

/// iOS 26 Liquid Glass Surface Modifier with Classic Native fallback
public struct LiquidGlassModifier: ViewModifier {
    @AppStorage("appDesignTheme") private var appDesignTheme: String = "liquidGlass"

    public var cornerRadius: CGFloat = 18
    public var isHighlighted: Bool = false
    public var tintColor: Color? = nil
    public var specularOpacity: Double = 0.22

    public func body(content: Content) -> some View {
        if appDesignTheme == "classicNative" {
            // Clean native fallback for older iOS and users preferring legacy native design
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isHighlighted ? Color.accentColor : Color(UIColor.separator).opacity(0.35),
                            lineWidth: isHighlighted ? 1.2 : 0.8
                        )
                        .allowsHitTesting(false)
                )
        } else {
            // iOS 26 Liquid Glass Surface Modifier
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(
                    ZStack {
                        // Translucent glass foundation
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground).opacity(0.18))

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

/// iOS 26 Deep Spatial Glass Background (with Classic Native fallback)
public struct LiquidAmbientBackground: View {
    @AppStorage("appDesignTheme") private var appDesignTheme: String = "liquidGlass"

    public init() {}

    public var body: some View {
        ZStack {
            if appDesignTheme == "classicNative" {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            } else {
                // Deep spatial midnight canvas (not flat pitch black)
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.09, blue: 0.14),
                        Color(red: 0.04, green: 0.05, blue: 0.08),
                        Color(red: 0.06, green: 0.06, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Top ambient purple/accent glow behind navigation and tool status
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.clear],
                    center: .top,
                    startRadius: 30,
                    endRadius: 380
                )
                .ignoresSafeArea()

                // Bottom ambient cyan glow behind the input field
                RadialGradient(
                    colors: [Color.cyan.opacity(0.12), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 40,
                    endRadius: 400
                )
                .ignoresSafeArea()
            }
        }
    }
}
