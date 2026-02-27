import SwiftUI

enum GlassCardStyle {
    case regular
    case elevated
    case subtle

    var glass: Glass {
        switch self {
        case .regular:
            return .regular
        case .elevated:
            return .regular.tint(.teal.opacity(0.14))
        case .subtle:
            return .clear
        }
    }

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
            .glassEffect(style.glass, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(style.strokeOpacity), lineWidth: 1)
            }
    }
}
