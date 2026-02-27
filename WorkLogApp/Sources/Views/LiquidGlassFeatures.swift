import SwiftUI

struct AdaptiveGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
#if EXPERIMENTAL_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

extension View {
    @ViewBuilder
    func adaptivePrimaryButtonStyle() -> some View {
#if EXPERIMENTAL_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
#else
        buttonStyle(.borderedProminent)
#endif
    }

    @ViewBuilder
    func adaptiveSecondaryButtonStyle() -> some View {
#if EXPERIMENTAL_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
#else
        buttonStyle(.bordered)
#endif
    }

    @ViewBuilder
    func adaptiveTabBarBehavior() -> some View {
#if EXPERIMENTAL_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
#else
        self
#endif
    }

    @ViewBuilder
    func adaptiveGlassUnion(id: String, namespace: Namespace.ID) -> some View {
#if EXPERIMENTAL_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            glassEffectUnion(id: id, namespace: namespace)
        } else {
            self
        }
#else
        self
#endif
    }
}
