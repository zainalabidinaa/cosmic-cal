import SwiftUI

struct LiquidBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.12, blue: 0.2),
                    Color(red: 0.04, green: 0.18, blue: 0.17),
                    Color(red: 0.02, green: 0.06, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.28))
                .frame(width: 320, height: 320)
                .offset(x: 140, y: -280)
                .blur(radius: 36)

            Circle()
                .fill(Color.teal.opacity(0.2))
                .frame(width: 280, height: 280)
                .offset(x: -140, y: 260)
                .blur(radius: 44)
        }
        .ignoresSafeArea()
    }
}
