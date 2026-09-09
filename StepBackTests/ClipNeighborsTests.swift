@testable import StepBack
import SwiftData
import XCTest

/// Swiping between clips in the player: which clip is next, and what
/// counts as a swipe.
@MainActor
final class ClipNeighborsTests: XCTestCase {

    private var container: ModelContainer!
    private var clips: [DanceClip] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: DanceClip.self, Tag.self, ClipSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        clips = ["a", "b", "c"].map { DanceClip(title: $0, assetIdentifier: $0) }
        clips.forEach { container.mainContext.insert($0) }
    }

    override func tearDown() async throws {
        clips = []
        container = nil
    }

    // MARK: - Neighbours

    func testMiddleClipHasBothNeighbours() {
        let neighbors = ClipNeighbors(of: clips[1], in: clips)
        XCTAssertEqual(neighbors.previous?.id, clips[0].id)
        XCTAssertEqual(neighbors.next?.id, clips[2].id)
    }

    func testEndsHaveOneNeighbourEach() {
        let first = ClipNeighbors(of: clips[0], in: clips)
        XCTAssertNil(first.previous)
        XCTAssertEqual(first.next?.id, clips[1].id)

        let last = ClipNeighbors(of: clips[2], in: clips)
        XCTAssertEqual(last.previous?.id, clips[1].id)
        XCTAssertNil(last.next)
    }

    func testClipOutsideTheListHasNoNeighbours() {
        let stranger = DanceClip(title: "z", assetIdentifier: "z")
        XCTAssertEqual(ClipNeighbors(of: stranger, in: clips), .none)
        XCTAssertEqual(ClipNeighbors(of: clips[0], in: []), .none)
    }

    func testNeighboursFollowTheOrderGiven() {
        // The Library's filtered order, not date order: whatever the grid
        // shows is what a swipe moves through.
        let reversed = Array(clips.reversed())
        XCTAssertEqual(ClipNeighbors(of: clips[2], in: reversed).next?.id, clips[1].id)
    }

    // MARK: - Swipe recognition

    func testLeftSwipeGoesToNextAndRightToPrevious() {
        XCTAssertEqual(PlayerSwipe.direction(for: CGSize(width: -120, height: 5), isZoomed: false), .toNext)
        XCTAssertEqual(PlayerSwipe.direction(for: CGSize(width: 90, height: -10), isZoomed: false), .toPrevious)
    }

    func testShortOrDiagonalDragsAreNotSwipes() {
        XCTAssertNil(PlayerSwipe.direction(for: CGSize(width: -40, height: 0), isZoomed: false), "too short")
        XCTAssertNil(PlayerSwipe.direction(for: CGSize(width: -80, height: 70), isZoomed: false), "too vertical")
        XCTAssertNil(PlayerSwipe.direction(for: CGSize(width: 0, height: -200), isZoomed: false), "a scroll")
    }

    func testDragsWhileZoomedPanRatherThanPage() {
        XCTAssertNil(PlayerSwipe.direction(for: CGSize(width: -200, height: 0), isZoomed: true))
    }

    func testTravelThresholdIsInclusive() {
        XCTAssertEqual(
            PlayerSwipe.direction(for: CGSize(width: -PlayerSwipe.minimumTravel, height: 0), isZoomed: false),
            .toNext
        )
    }
}
