@testable import StepBack
import SwiftData
import XCTest

@MainActor
final class ModelsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: DanceClip.self, Tag.self, LoopMarker.self,
            configurations: config
        )
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: - DanceClip

    func testDanceClipDefaults() throws {
        let clip = DanceClip(title: "Warmup", assetIdentifier: "ASSET-1")
        context.insert(clip)
        try context.save()

        XCTAssertEqual(clip.title, "Warmup")
        XCTAssertEqual(clip.assetIdentifier, "ASSET-1")
        XCTAssertEqual(clip.notes, "")
        XCTAssertNil(clip.eventName)
        XCTAssertNil(clip.thumbnailData)
        XCTAssertEqual(clip.durationSeconds, 0)
        XCTAssertTrue(clip.loopMarkers.isEmpty)
        XCTAssertTrue(clip.tags.isEmpty)
    }

    // MARK: - LoopMarker

    func testLoopMarkerRelationshipAndCascadeDelete() throws {
        let clip = DanceClip(title: "Practice", assetIdentifier: "ASSET-2")
        let marker = LoopMarker(
            label: "Hard 8-count",
            startSeconds: 10,
            endSeconds: 18,
            preferredSpeed: 0.5,
            clip: clip
        )
        clip.loopMarkers.append(marker)
        context.insert(clip)
        try context.save()

        XCTAssertEqual(clip.loopMarkers.count, 1)
        XCTAssertIdentical(marker.clip, clip)
        XCTAssertEqual(marker.durationSeconds, 8, accuracy: 0.0001)

        context.delete(clip)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<LoopMarker>())
        XCTAssertTrue(remaining.isEmpty, "Deleting the clip should cascade to its markers")
    }

    func testLoopMarkerDurationNeverNegative() {
        let marker = LoopMarker(label: "Weird", startSeconds: 10, endSeconds: 5)
        XCTAssertEqual(marker.durationSeconds, 0)
    }

    // MARK: - Tag

    func testTagManyToManyWithClips() throws {
        let tag = Tag(name: "Event: Sep 5, 2025", colorHex: "#FF3B7F")
        let clipA = DanceClip(title: "A", assetIdentifier: "A")
        let clipB = DanceClip(title: "B", assetIdentifier: "B")

        context.insert(tag)
        context.insert(clipA)
        context.insert(clipB)
        tag.clips.append(contentsOf: [clipA, clipB])
        try context.save()

        XCTAssertEqual(tag.clips.count, 2)
        XCTAssertTrue(clipA.tags.contains { $0.id == tag.id })
        XCTAssertTrue(clipB.tags.contains { $0.id == tag.id })
    }

    func testDeletingTagDoesNotDeleteClips() throws {
        let tag = Tag(name: "Lindy basics", colorHex: "#5FE7FF")
        let clip = DanceClip(title: "Clip", assetIdentifier: "ASSET-3")
        context.insert(tag)
        context.insert(clip)
        tag.clips.append(clip)
        try context.save()

        context.delete(tag)
        try context.save()

        let clips = try context.fetch(FetchDescriptor<DanceClip>())
        XCTAssertEqual(clips.count, 1)
        XCTAssertTrue(clips[0].tags.isEmpty)
    }
}
