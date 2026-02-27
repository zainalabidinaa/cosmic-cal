import SwiftUI

struct DarkBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(white: 0.11), Color(white: 0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
