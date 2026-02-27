import SwiftUI

enum GlassCardStyle {
    case regular
    case elevated
    case subtle

    var strokeOpacity: Double {
        switch self {
        case .regular:
            return 0.22
        case .elevated:
            return 0.3
        case .subtle:
            return 0.16
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
        content
            .padding(16)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(style.strokeOpacity), lineWidth: 1)
            }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch style {
        case .regular:
            return AnyShapeStyle(.ultraThinMaterial)
        case .elevated:
            return AnyShapeStyle(Color.teal.opacity(0.12))
        case .subtle:
            return AnyShapeStyle(Color.white.opacity(0.06))
        }
    }
}
