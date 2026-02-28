import SwiftUI

struct LiquidBackdrop: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.06),
                    Color(red: 0.08, green: 0.08, blue: 0.09),
                    Color(red: 0.15, green: 0.11, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.22), .yellow.opacity(0.08)],
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
                        colors: [.brown.opacity(0.2), .orange.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 340, height: 240)
                .offset(x: drift ? -170 : -120, y: drift ? 300 : 250)
                .blur(radius: 48)

            RoundedRectangle(cornerRadius: 240, style: .continuous)
                .fill(
                    AngularGradient(
                        colors: [.white.opacity(0.14), .yellow.opacity(0.1), .clear, .white.opacity(0.08)],
                        center: .center
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: drift ? 120 : 70, y: drift ? 90 : 130)
                .blur(radius: 44)

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
