import SwiftUI

struct CosmicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.01, green: 0.02, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.13), Color.clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 640
            )

            RadialGradient(
                colors: [Color.mint.opacity(0.11), Color.clear],
                center: .bottomLeading,
                startRadius: 25,
                endRadius: 590
            )
        }
        .ignoresSafeArea()
    }
}
