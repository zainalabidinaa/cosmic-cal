import SwiftUI

enum GlassCardStyle {
    case regular
    case elevated
    case subtle

    var strokeOpacity: Double {
        switch self {
        case .regular:
            return 0.18
        case .elevated:
            return 0.24
        case .subtle:
            return 0.12
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .regular:
            return 0.18
        case .elevated:
            return 0.26
        case .subtle:
            return 0.10
        }
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content
    private let style: GlassCardStyle

    init(style: GlassCardStyle = .regular, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        Group {
#if EXPERIMENTAL_LIQUID_GLASS
            if #available(iOS 26.0, *) {
                content
                    .padding(16)
                    .glassEffect(liquidGlass, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(style.shadowOpacity), radius: 20, x: 0, y: 10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(style.strokeOpacity), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.14), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.screen)
                            .allowsHitTesting(false)
                    }
            } else {
                fallbackCard
            }
#else
            fallbackCard
#endif
        }
    }

    private var fallbackCard: some View {
        content
            .padding(16)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(style.shadowOpacity * 0.9), radius: 16, x: 0, y: 8)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(style.strokeOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

#if EXPERIMENTAL_LIQUID_GLASS
    @available(iOS 26.0, *)
    private var liquidGlass: Glass {
        switch style {
        case .regular:
            return .regular
        case .elevated:
            return .regular.tint(GraphiteCopperTheme.copper.opacity(0.18))
        case .subtle:
            return .clear
        }
    }
#endif

    private var backgroundStyle: AnyShapeStyle {
        switch style {
        case .regular:
            return AnyShapeStyle(.ultraThinMaterial)
        case .elevated:
            return AnyShapeStyle(GraphiteCopperTheme.copper.opacity(0.14))
        case .subtle:
            return AnyShapeStyle(Color.white.opacity(0.05))
        }
    }
}
