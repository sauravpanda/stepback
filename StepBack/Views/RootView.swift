import SwiftUI

struct RootView: View {
    var body: some View {
        LibraryView()
            .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
}
