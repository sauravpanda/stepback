import SwiftUI
import UIKit

// MARK: - Cell

enum CellSelectionState {
    case hidden
    case selected
    case unselected
}

struct LibraryCell: View {
    let clip: DanceClip
    var selectionState: CellSelectionState = .hidden
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleFavorite: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Theme.Color.surfaceElevated
                thumbnail
                if selectionState == .selected {
                    Theme.Color.accent.opacity(0.25)
                }
                VStack {
                    HStack(alignment: .top) {
                        if selectionState != .hidden {
                            selectionIndicator
                        } else {
                            if clip.isFavorite {
                                favoriteBadge
                            }
                            if !clip.segments.isEmpty {
                                patternsBadge
                            }
                        }
                        Spacer()
                        if selectionState == .hidden, onEdit != nil || onDelete != nil {
                            menuButton
                        }
                    }
                    Spacer()
                    HStack {
                        if !clip.tags.isEmpty {
                            tagChips
                        }
                        Spacer()
                        durationBadge
                    }
                }
                .padding(6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                    .stroke(Theme.Color.accent, lineWidth: selectionState == .selected ? 2 : 0)
            )

            Text(clip.title)
                .font(Theme.Font.bodyEmphasized)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(LibraryFormatter.shortDate(clip.dateAdded))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The image is drawn as an overlay on a clear view sized to the cell
    /// rather than laid out directly: a `scaledToFill` image reports its
    /// *filled* size (wider than the cell for landscape video) up to the
    /// grid, which then lets it spill over its neighbours. The clear base
    /// only ever reports the cell's own size, and `clipped` trims the
    /// overflow to it.
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
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private var durationBadge: some View {
        Text(LibraryFormatter.duration(clip.durationSeconds))
            .font(Theme.Font.timestamp)
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.55), in: Capsule())
    }

    /// Top-left chip showing how many saved patterns this clip has. Hidden
    /// when the clip has none — a clip without patterns is the empty case,
    /// not a state worth surfacing.
    private var patternsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "scissors")
                .font(.system(size: 10, weight: .semibold))
            Text("\(clip.segments.count)")
                .font(Theme.Font.timestamp)
        }
        .foregroundStyle(Theme.Color.textPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.55), in: Capsule())
        .accessibilityLabel("\(clip.segments.count) pattern\(clip.segments.count == 1 ? "" : "s")")
    }

    /// Top-left heart on a favourited clip. The menu is where you *make* a
    /// favourite; this is how you can tell at a glance that you did.
    private var favoriteBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Color.accent)
            .frame(width: 22, height: 22)
            .background(Color.black.opacity(0.55), in: Circle())
            .accessibilityLabel("Favorite")
    }

    private var selectionIndicator: some View {
        Image(systemName: selectionState == .selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(selectionState == .selected ? Theme.Color.accent : Color.white.opacity(0.85))
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }

    private var menuButton: some View {
        Menu {
            if let onToggleFavorite {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(
                        clip.isFavorite ? "Remove from Favorites" : "Favorite",
                        systemImage: clip.isFavorite ? "heart.slash" : "heart"
                    )
                }
            }
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .menuStyle(.borderlessButton)
    }

    private var tagChips: some View {
        HStack(spacing: 3) {
            ForEach(clip.tags.prefix(3)) { tag in
                Circle()
                    .fill(Color(tagHex: tag.colorHex))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
    }
}
