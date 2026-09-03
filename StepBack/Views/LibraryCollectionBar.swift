import SwiftData
import SwiftUI

/// What the Library grid is showing: everything, the favourites, or one
/// album.
///
/// One collection at a time, because "easy access" means one tap to the
/// clips you want, not a filter you compose. Albums are the existing `Tag`
/// records — the user sees albums, the store still calls them tags.
enum LibraryCollection: Hashable {
    case all
    case favorites
    case album(UUID)
    /// Clips that aren't in any album — the pile still to be filed.
    case unfiled

    func contains(_ clip: DanceClip) -> Bool {
        switch self {
        case .all: true
        case .favorites: clip.isFavorite
        case .album(let id): clip.tags.contains { $0.id == id }
        case .unfiled: clip.tags.isEmpty
        }
    }

    /// What to say when the collection has nothing in it. Nil for `.all`,
    /// whose empty state is the import prompt.
    var emptyHint: String? {
        switch self {
        case .all: nil
        case .favorites: "No favorites yet. Open a clip's ⋯ menu and choose Favorite."
        case .album: "Nothing in this album yet. Add clips from their ⋯ menu, or Select and Move."
        case .unfiled: "Everything is in an album."
        }
    }
}

/// The row of collections under the Library title: All, Favorites, one
/// chip per album, and — only while there are any — the clips not yet in
/// an album. Each shows its count. Tapping a chip shows just that
/// collection; tapping it again does nothing, because there's always
/// exactly one collection showing.
struct LibraryCollectionBar: View {
    let albums: [Tag]
    let clips: [DanceClip]
    @Binding var selected: LibraryCollection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, label: "All", tint: .white) {
                    EmptyView()
                }
                chip(.favorites, label: "Favorites", tint: Theme.Color.accent) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                ForEach(albums) { album in
                    chip(.album(album.id), label: album.name, tint: Color(tagHex: album.colorHex)) {
                        Circle().frame(width: 8, height: 8)
                    }
                }
                // Last, after the albums you made: the pile still to file.
                // Hidden once it's empty, so a tidy library isn't nagged.
                if selected == .unfiled || clips.contains(where: LibraryCollection.unfiled.contains) {
                    chip(.unfiled, label: "No album", tint: Theme.Color.speedCyan) {
                        Image(systemName: "tray")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.Color.background)
    }

    private func chip<Leading: View>(
        _ collection: LibraryCollection,
        label: String,
        tint: Color,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        let isSelected = selected == collection
        let count = clips.filter(collection.contains).count
        return Button {
            selected = collection
        } label: {
            HStack(spacing: 6) {
                leading()
                    .foregroundStyle(isSelected ? .black : tint)
                Text(label)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                Text("\(count)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(isSelected ? .black.opacity(0.6) : Theme.Color.textTertiary)
            }
            .foregroundStyle(isSelected ? .black : Theme.Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(isSelected ? tint : Theme.Color.surfaceElevated))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count) video\(count == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Shown in place of the grid when the chosen collection is empty.
struct LibraryCollectionEmptyState: View {
    let hint: String

    var body: some View {
        Text(hint)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 48)
            .frame(maxWidth: .infinity)
    }
}
