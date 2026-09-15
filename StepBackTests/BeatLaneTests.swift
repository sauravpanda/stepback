@testable import StepBack
import XCTest

/// The pure parts of the beat lane drawn over the Practice video.
final class BeatLaneTests: XCTestCase {

    private let beats: [Double] = (0..<40).map { Double($0) * 0.5 }

    // MARK: - Roles

    func testPhraseStartOutranksCountStartOutranksBeat() {
        let counts: Set<Int> = [0, 8, 16]
        let phrases: Set<Int> = [0]
        XCTAssertEqual(BeatLaneGeometry.role(of: 0, countStarts: counts, phraseStarts: phrases), .phrase)
        XCTAssertEqual(BeatLaneGeometry.role(of: 8, countStarts: counts, phraseStarts: phrases), .count)
        XCTAssertEqual(BeatLaneGeometry.role(of: 3, countStarts: counts, phraseStarts: phrases), .beat)
    }

    func testPhraseIsTallestAndBrightest() {
        XCTAssertGreaterThan(BeatLaneRole.phrase.heightFraction, BeatLaneRole.count.heightFraction)
        XCTAssertGreaterThan(BeatLaneRole.count.heightFraction, BeatLaneRole.beat.heightFraction)
        XCTAssertEqual(BeatLaneRole.phrase.heightFraction, 1)
    }

    // MARK: - Visible window

    func testVisibleIndicesCoverTheWindowEitherSideOfNow() {
        // Now = 5.0s, window 2s: beats from 3.0 to 7.0 inclusive, i.e.
        // indices 6 through 14.
        XCTAssertEqual(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 5.0, window: 2.0), 6..<15)
    }

    func testVisibleIndicesClampAtTheEnds() {
        XCTAssertEqual(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 0.0, window: 2.0), 0..<5)
        XCTAssertEqual(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 19.5, window: 2.0), 35..<40)
    }

    func testVisibleIndicesAreEmptyOutsideTheGridOrWithoutOne() {
        XCTAssertTrue(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 100, window: 2.0).isEmpty)
        XCTAssertTrue(BeatLaneGeometry.visibleIndices(beatTimes: [], around: 1, window: 2.0).isEmpty)
    }

    func testVisibleIndicesMatchABruteForceScan() {
        for now in stride(from: -1.0, through: 21.0, by: 0.37) {
            let expected = beats.indices.filter { abs(beats[$0] - now) <= 2.0 }
            let actual = Array(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: now, window: 2.0))
            XCTAssertEqual(actual, expected, "at \(now)")
        }
    }
}
