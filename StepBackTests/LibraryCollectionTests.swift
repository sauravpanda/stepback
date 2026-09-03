@testable import StepBack
import SwiftData
import XCTest

/// The Library's collections: All, Favorites, and one chip per album.
@MainActor
final class LibraryCollectionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: DanceClip.self, Tag.self, ClipSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() async throws {
        container = nil
    }

    private func clip(_ title: String, favorite: Bool = false, in album: Tag? = nil) -> DanceClip {
        let clip = DanceClip(title: title, assetIdentifier: title)
        clip.isFavorite = favorite
        if let album {
            clip.tags.append(album)
        }
        context.insert(clip)
        return clip
    }

    func testAllContainsEverything() {
        let blues = Tag(name: "Blues", colorHex: "#5FE7FF")
        context.insert(blues)
        let clips = [clip("a"), clip("b", favorite: true), clip("c", in: blues)]
        XCTAssertEqual(clips.filter(LibraryCollection.all.contains).count, 3)
    }

    func testFavoritesContainsOnlyStarredClips() {
        let starred = clip("starred", favorite: true)
        let plain = clip("plain")
        XCTAssertTrue(LibraryCollection.favorites.contains(starred))
        XCTAssertFalse(LibraryCollection.favorites.contains(plain))
    }

    func testAlbumContainsOnlyItsOwnClips() {
        let blues = Tag(name: "Blues", colorHex: "#5FE7FF")
        let pop = Tag(name: "Pop", colorHex: "#FFA13B")
        context.insert(blues)
        context.insert(pop)
        let inBlues = clip("blues", in: blues)
        let inPop = clip("pop", in: pop)
        let inNeither = clip("loose")

        let album = LibraryCollection.album(blues.id)
        XCTAssertTrue(album.contains(inBlues))
        XCTAssertFalse(album.contains(inPop))
        XCTAssertFalse(album.contains(inNeither))
    }

    func testUnfiledContainsOnlyClipsInNoAlbum() {
        let blues = Tag(name: "Blues", colorHex: "#5FE7FF")
        context.insert(blues)
        let filed = clip("filed", in: blues)
        let loose = clip("loose")
        let looseFavorite = clip("loose favorite", favorite: true)

        XCTAssertFalse(LibraryCollection.unfiled.contains(filed))
        XCTAssertTrue(LibraryCollection.unfiled.contains(loose))
        XCTAssertTrue(LibraryCollection.unfiled.contains(looseFavorite), "favourites still need filing")
    }

    func testFilingAClipDropsItFromUnfiled() {
        let blues = Tag(name: "Blues", colorHex: "#5FE7FF")
        context.insert(blues)
        let loose = clip("loose")
        XCTAssertTrue(LibraryCollection.unfiled.contains(loose))
        loose.tags.append(blues)
        XCTAssertFalse(LibraryCollection.unfiled.contains(loose))
    }

    func testUnfavoritingDropsAClipFromFavorites() {
        let starred = clip("starred", favorite: true)
        starred.isFavorite = false
        XCTAssertFalse(LibraryCollection.favorites.contains(starred))
    }

    func testOnlyAllHasNoEmptyHint() {
        // "All" being empty means the library is empty, which the import
        // prompt already covers; the others need to tell you how to fill them.
        XCTAssertNil(LibraryCollection.all.emptyHint)
        XCTAssertNotNil(LibraryCollection.favorites.emptyHint)
        XCTAssertNotNil(LibraryCollection.album(UUID()).emptyHint)
        XCTAssertNotNil(LibraryCollection.unfiled.emptyHint)
    }

    func testIsFavoritePersistsAcrossSave() throws {
        let starred = clip("starred", favorite: true)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<DanceClip>())
        XCTAssertEqual(fetched.first?.id, starred.id)
        XCTAssertEqual(fetched.first?.isFavorite, true)
    }
}
