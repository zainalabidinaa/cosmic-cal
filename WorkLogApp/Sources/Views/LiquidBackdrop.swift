import SwiftUI

struct LiquidBackdrop: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    GraphiteCopperTheme.graphite900,
                    GraphiteCopperTheme.graphite800,
                    GraphiteCopperTheme.graphite700
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [GraphiteCopperTheme.copper.opacity(0.34), GraphiteCopperTheme.amber.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 420, height: 300)
                .offset(x: drift ? 120 : 180, y: drift ? -300 : -360)
                .blur(radius: 56)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [GraphiteCopperTheme.copperSoft.opacity(0.22), GraphiteCopperTheme.graphite900.opacity(0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 360, height: 260)
                .offset(x: drift ? -180 : -120, y: drift ? 330 : 290)
                .blur(radius: 62)

            RoundedRectangle(cornerRadius: 240, style: .continuous)
                .fill(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.12),
                            GraphiteCopperTheme.copperSoft.opacity(0.12),
                            .clear,
                            .white.opacity(0.06)
                        ],
                        center: .center
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: drift ? 80 : 20, y: drift ? 150 : 210)
                .blur(radius: 54)

            Ellipse()
                .fill(GraphiteCopperTheme.amber.opacity(0.07))
                .frame(width: 260, height: 120)
                .offset(x: drift ? -40 : 30, y: drift ? 420 : 360)
                .blur(radius: 34)

#if EXPERIMENTAL_LIQUID_GLASS
            if #available(iOS 26.0, *) {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 500, height: 150)
                    .rotationEffect(.degrees(-10))
                    .offset(x: drift ? -20 : 40, y: drift ? -120 : -170)
                    .blur(radius: 20)
                    .blendMode(.screen)
            }
#endif
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}
