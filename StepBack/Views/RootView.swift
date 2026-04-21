import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Wordmark()
                Text("Scaffold ready.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("Library lands in issue #4.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }
}

private struct Wordmark: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("STEP").foregroundStyle(Theme.Color.accent)
            Text("BACK").foregroundStyle(Theme.Color.textPrimary)
        }
        .font(.system(size: 38, weight: .black, design: .rounded))
        .tracking(-1)
    }
}

#Preview {
    RootView()
}
