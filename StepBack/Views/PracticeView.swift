import SwiftUI

struct PracticeView: View {
    let clip: DanceClip

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.Color.accent)
                Text(clip.title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Player lands in issue #5.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding()
        }
        .navigationTitle(clip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
