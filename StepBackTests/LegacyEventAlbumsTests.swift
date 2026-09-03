@testable import StepBack
import SwiftData
import XCTest

@MainActor
final class LegacyEventAlbumsTests: XCTestCase {

    func testRecognisesTheOldClusteringNames() {
        XCTAssertTrue(LegacyEventAlbums.isLegacyName("Event: Sep 2, 2026"))
        XCTAssertTrue(LegacyEventAlbums.isLegacyName("Event: Dec 25, 2025"))
        // Locales that abbreviate with a full stop.
        XCTAssertTrue(LegacyEventAlbums.isLegacyName("Event: sept. 2, 2026"))
    }

    func testLeavesAlbumsPeopleNamedAlone() {
        XCTAssertFalse(LegacyEventAlbums.isLegacyName("Blues"))
        XCTAssertFalse(LegacyEventAlbums.isLegacyName("Event night"))
        XCTAssertFalse(LegacyEventAlbums.isLegacyName("Event: Friday"))
        XCTAssertFalse(LegacyEventAlbums.isLegacyName("Event: Sep 2"))
        XCTAssertFalse(LegacyEventAlbums.isLegacyName("event: sep 2, 2026 workshop"))
    }

    func testRemoveDeletesOnlyLegacyAlbumsAndKeepsClips() throws {
        let container = try ModelContainer(
            for: DanceClip.self, Tag.self, ClipSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let legacy = Tag(name: "Event: Sep 2, 2026", colorHex: "#5FE7FF")
        let mine = Tag(name: "Sugar push", colorHex: "#FF3B7F")
        let clip = DanceClip(title: "Class", assetIdentifier: "ASSET")
        clip.tags = [legacy, mine]
        context.insert(legacy)
        context.insert(mine)
        context.insert(clip)
        try context.save()

        let removed = LegacyEventAlbums.remove(from: [legacy, mine], in: context)
        try context.save()

        XCTAssertEqual(removed, 1)
        let albums = try context.fetch(FetchDescriptor<Tag>())
        XCTAssertEqual(albums.map(\.name), ["Sugar push"])
        let clips = try context.fetch(FetchDescriptor<DanceClip>())
        XCTAssertEqual(clips.count, 1, "removing an album never removes a clip")
        XCTAssertEqual(clips.first?.tags.map(\.name), ["Sugar push"])
    }

    func testRemoveIsIdempotent() throws {
        let container = try ModelContainer(
            for: DanceClip.self, Tag.self, ClipSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let mine = Tag(name: "Blues", colorHex: "#FF3B7F")
        container.mainContext.insert(mine)
        XCTAssertEqual(LegacyEventAlbums.remove(from: [mine], in: container.mainContext), 0)
    }
}
