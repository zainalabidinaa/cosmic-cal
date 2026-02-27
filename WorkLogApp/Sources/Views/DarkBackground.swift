// DarkBackground is no longer used on iOS 26.
// The system provides the correct adaptive background automatically.
// This file is kept as a no-op stub for build compatibility.
import SwiftUI

@available(*, deprecated, message: "Not used on iOS 26. Remove call sites.")
struct DarkBackground: View {
    var body: some View {
        Color.clear
    }
}
