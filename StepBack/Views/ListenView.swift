import SwiftData
import SwiftUI
import UIKit

/// The Listen tab: pick a clip, then drill your ear against its beat grid.
///
/// Deliberately a thin picker. Everything else — detecting beats, placing
/// beat 1, running a drill — happens on one screen in `ListeningDrillView`,
/// so there is only ever a single AVPlayer alive in this tab.
struct ListenView: View {

    @Query(sort: \DanceClip.dateAdded, order: .reverse) private var clips: [DanceClip]

    var body: some View {
        NavigationStack {
            content
                .background(Theme.Color.background.ignoresSafeArea())
                .navigationTitle("Listen")
                .toolbarBackground(Theme.Color.background, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .navigationDestination(for: DanceClip.self) { clip in
                    ListeningDrillView(clip: clip)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if clips.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    intro
                    ForEach(clips) { clip in
                        NavigationLink(value: clip) {
                            ListeningClipRow(clip: clip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var intro: some View {
        Text("Train the musical half: find beat 1, hear the phrase turn over, hold the count on your own.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "ear")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("Nothing to listen to yet")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Import a clip in the Library tab. Any clip with audio works — the drills run off its beat grid.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct ListeningClipRow: View {
    let clip: DanceClip

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(Theme.Font.bodyEmphasized)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let bpm = clip.bpm {
                        Text("\(Int(bpm.rounded())) BPM")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                    Text(LibraryFormatter.duration(clip.durationSeconds))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                ReadinessBadge(readiness: ListeningReadiness(clip: clip))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(10)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Theme.Color.surfaceElevated
            if let data = clip.thumbnailData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
