import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .listeningTabBarStyle()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            ListenView()
                .listeningTabBarStyle()
                .tabItem { Label("Listen", systemImage: "ear") }
        }
        .tint(Theme.Color.accent)
        .preferredColorScheme(.dark)
    }
}

private extension View {
    /// The tab bar defaults to a light material even under
    /// `.preferredColorScheme(.dark)`, which reads as a grey band under the
    /// app's near-black surfaces. Pinning it visible in the theme colour
    /// keeps the chrome continuous with the content.
    func listeningTabBarStyle() -> some View {
        toolbarBackground(Theme.Color.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

#Preview {
    RootView()
}
