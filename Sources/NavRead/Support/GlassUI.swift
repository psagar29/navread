import SwiftUI

// MARK: - Design Tokens

enum NavReadTheme {
    static let cornerRadiusSmall: CGFloat = 12
    static let cornerRadiusMedium: CGFloat = 20
    static let cornerRadiusLarge: CGFloat = 28
    static let cornerRadiusXL: CGFloat = 36

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 14
    static let spacingLG: CGFloat = 20
    static let spacingXL: CGFloat = 28
    static let spacingXXL: CGFloat = 40

    static let animationSpring = Animation.spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0.1)
    static let animationSnappy = Animation.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0)
    static let animationGentle = Animation.spring(response: 0.6, dampingFraction: 0.72, blendDuration: 0.15)
    static let animationBouncy = Animation.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0)
}

// MARK: - Glass Panel (Premium Glassmorphism)

struct GlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = NavReadTheme.cornerRadiusLarge
    var padding: CGFloat = 18
    var intensity: GlassIntensity = .regular
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background { materialBackground }
            .clipShape(shape)
            .overlay(shape.strokeBorder(borderGradient, lineWidth: intensity == .thin ? 0.5 : 1))
            .shadow(color: outerShadow, radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: innerGlow, radius: 1, x: 0, y: -0.5)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var materialBackground: some View {
        switch intensity {
        case .ultraThin:
            shape.fill(.ultraThinMaterial)
        case .thin:
            shape.fill(.thinMaterial)
        case .regular:
            shape.fill(.regularMaterial)
        case .thick:
            shape.fill(.thickMaterial)
        }
    }

    private var borderGradient: LinearGradient {
        if colorScheme == .dark {
            LinearGradient(
                colors: [.white.opacity(0.22), .white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [.white.opacity(0.8), .black.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var outerShadow: Color {
        colorScheme == .dark ? .black.opacity(0.28) : .black.opacity(0.06)
    }

    private var innerGlow: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.5)
    }

    private var shadowRadius: CGFloat {
        switch intensity {
        case .ultraThin: 8
        case .thin: 14
        case .regular: 22
        case .thick: 30
        }
    }

    private var shadowY: CGFloat {
        switch intensity {
        case .ultraThin: 4
        case .thin: 6
        case .regular: 10
        case .thick: 14
        }
    }
}

enum GlassIntensity {
    case ultraThin, thin, regular, thick
}

// MARK: - Liquid Button Style (Premium)

struct LiquidButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)
                    Capsule()
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.04))
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(configuration.isPressed ? 0.26 : 0.16),
                                Color.primary.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.primary.opacity(configuration.isPressed ? 0 : (colorScheme == .dark ? 0.10 : 0.06)), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(NavReadTheme.animationSnappy, value: configuration.isPressed)
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? inverseInk : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isEnabled
                                ? [ink, ink.opacity(0.84)]
                                : [Color.secondary.opacity(0.14), Color.secondary.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isEnabled ? ink.opacity(configuration.isPressed ? 0 : 0.18) : .clear, radius: 12, y: 6)
            )
            .overlay(
                Capsule()
                    .strokeBorder((isEnabled ? inverseInk.opacity(0.2) : Color.primary.opacity(0.08)), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(NavReadTheme.animationSnappy, value: configuration.isPressed)
    }

    private var ink: Color {
        colorScheme == .dark ? .white : .black
    }

    private var inverseInk: Color {
        colorScheme == .dark ? .black : .white
    }
}

// MARK: - Ghost Button Style

struct GhostButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? Color.primary.opacity(0.06) : .clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.2 : 0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(NavReadTheme.animationSnappy, value: configuration.isPressed)
    }
}

// MARK: - Ink Scan View (AI Activity Indicator)

struct InkScanView: View {
    @State private var phase = false
    @State private var dotPhase = 0.0

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.12))
                    .frame(width: 80, height: 5)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.primary.opacity(0.72), .primary.opacity(0.38)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: phase ? 80 : 16, height: 5)
                    .shadow(color: .primary.opacity(0.18), radius: 4, y: 0)
            }
            HStack(spacing: 3) {
                Text("AI")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text("reading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 3, height: 3)
                        .offset(y: dotPhase.truncatingRemainder(dividingBy: 3) == Double(i) ? -2 : 0)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                phase = true
            }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                dotPhase = 3
            }
        }
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5
    var active: Bool = true

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if active {
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.12), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .offset(x: phase * 300)
                        .mask(content)
                    }
                }
            )
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

// MARK: - Floating Card Modifier

struct FloatingCardModifier: ViewModifier {
    @State private var isHovering = false
    var liftAmount: CGFloat = 4
    var scaleAmount: CGFloat = 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scaleAmount : 1)
            .shadow(
                color: .black.opacity(isHovering ? 0.12 : 0.06),
                radius: isHovering ? 20 : 10,
                y: isHovering ? 10 : 5
            )
            .offset(y: isHovering ? -liftAmount : 0)
            .animation(NavReadTheme.animationSpring, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func floatingCard(lift: CGFloat = 4, scale: CGFloat = 1.02) -> some View {
        modifier(FloatingCardModifier(liftAmount: lift, scaleAmount: scale))
    }
}

// MARK: - Morphing Background

struct MorphingBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var accentHex: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: baseColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025),
                    .clear,
                    Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor).opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.24 : 0.38)
        }
        .ignoresSafeArea()
    }

    private var baseColors: [Color] {
        if colorScheme == .dark {
            [
                Color.black.opacity(0.92),
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.95)
            ]
        } else {
            [
                Color.white,
                Color(nsColor: .textBackgroundColor),
                Color.white.opacity(0.95)
            ]
        }
    }
}

// MARK: - Premium Tag Pill

struct TagPill: View {
    var text: String
    var color: Color = .primary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.2), lineWidth: 0.5))
            .foregroundStyle(color)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    var title: String
    var subtitle: String = ""
    var icon: String = ""

    var body: some View {
        HStack(spacing: 8) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 16, weight: .bold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}

// MARK: - Premium Text Field Style

struct NavReadTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusSmall, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}
