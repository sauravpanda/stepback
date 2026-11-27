import SwiftUI
import UIKit

/// The row at the top of the Library: the handful of clips you actually
/// come back to, so they're one tap away in a library of hundreds. The
/// caller ranks them (`WatchRanking`) and hides the row when there are none.
struct LibraryRecentsRow: View {
    /// Already ranked, best first.
    let clips: [DanceClip]
    @Binding var order: WatchOrder
    let onOpen: (DanceClip) -> Void
    let onRemove: (DanceClip) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(clips) { clip in
                        Button {
                            onOpen(clip)
                        } label: {
                            RecentClipCard(clip: clip)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onRemove(clip)
                            } label: {
                                Label("Remove from Recently Watched", systemImage: "eye.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            // Re-ranking under a new order starts the row from its best clip
            // rather than wherever the old order had been scrolled to.
            .id(order)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack {
            Text("Recently Watched")
                .font(Theme.Font.bodyEmphasized)
                .foregroundStyle(Theme.Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Picker("Order", selection: $order) {
                    ForEach(WatchOrder.allCases) { option in
                        Label(option.label, systemImage: option.systemImage).tag(option)
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Clear Recently Watched", systemImage: "eye.slash")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: order.systemImage)
                        .font(.system(size: 11, weight: .bold))
                    Text(order.label)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.Color.surfaceElevated))
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Order Recently Watched, currently \(order.label)")
        }
        .padding(.horizontal, 16)
    }
}

/// One clip in the Recently Watched row: thumbnail, title, and how it's
/// been watched.
private struct RecentClipCard: View {
    let clip: DanceClip

    private static let width: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Theme.Color.surfaceElevated
                thumbnail
                Text(LibraryFormatter.duration(clip.durationSeconds))
                    .font(Theme.Font.timestamp)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(5)
            }
            .frame(width: Self.width, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))

            Text(clip.title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)
            Text(LibraryFormatter.watchSummary(clip.watchStats))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
                .lineLimit(1)
        }
        .frame(width: Self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Drawn over a clear base for the same reason as `LibraryCell`: a
    /// filled image reports its overflowing size to the stack otherwise.
    @ViewBuilder
    private var thumbnail: some View {
        if let data = clip.thumbnailData, let uiImage = UIImage(data: data) {
            Color.clear
                .overlay {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            Image(systemName: "film")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension LibraryFormatter {

    /// "3 views · 2 days ago" under a Recently Watched card.
    static func watchSummary(_ stats: WatchStats, now: Date = Date()) -> String {
        let noun = stats.count == 1 ? "view" : "views"
        let views = "\(stats.count) \(noun)"
        guard let last = stats.lastWatchedAt else { return views }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        // Inside a minute "now" reads better than "in 0 sec." / "0 sec. ago".
        let when = now.timeIntervalSince(last) < 60
            ? "just now"
            : formatter.localizedString(for: last, relativeTo: now)
        return "\(views) · \(when)"
    }
}
