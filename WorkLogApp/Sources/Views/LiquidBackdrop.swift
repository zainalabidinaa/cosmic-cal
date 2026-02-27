import SwiftUI

struct LiquidBackdrop: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.08, blue: 0.07),
                    Color(red: 0.13, green: 0.11, blue: 0.09),
                    Color(red: 0.17, green: 0.13, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.2), .yellow.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 360, height: 280)
                .offset(x: drift ? 120 : 170, y: drift ? -260 : -300)
                .blur(radius: 42)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [.pink.opacity(0.14), .orange.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 340, height: 240)
                .offset(x: drift ? -170 : -120, y: drift ? 300 : 250)
                .blur(radius: 48)

            Ellipse()
                .fill(Color.white.opacity(0.08))
                .frame(width: 240, height: 120)
                .offset(x: 0, y: drift ? 420 : 390)
                .blur(radius: 30)

#if EXPERIMENTAL_LIQUID_GLASS
            if #available(iOS 26.0, *) {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 460, height: 140)
                    .rotationEffect(.degrees(-12))
                    .offset(x: drift ? -40 : 20, y: drift ? -110 : -150)
                    .blur(radius: 24)
                    .blendMode(.screen)
            }
#endif
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}
