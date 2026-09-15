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

    func testPhraseIsTallestAndBrightestAndOnlyStartsAreLabelled() {
        XCTAssertGreaterThan(BeatLaneRole.phrase.heightFraction, BeatLaneRole.count.heightFraction)
        XCTAssertGreaterThan(BeatLaneRole.count.heightFraction, BeatLaneRole.beat.heightFraction)
        XCTAssertEqual(BeatLaneRole.phrase.heightFraction, 1)
        XCTAssertNil(BeatLaneRole.beat.label)
        XCTAssertEqual(BeatLaneRole.count.label, "1")
        XCTAssertEqual(BeatLaneRole.phrase.label, "phrase")
    }

    // MARK: - Which 8 of the phrase

    func testEightOfPhraseCountsInEights() {
        XCTAssertEqual(BeatLaneGeometry.eightOfPhrase(phrasePosition: 1, countLength: 8), 1)
        XCTAssertEqual(BeatLaneGeometry.eightOfPhrase(phrasePosition: 8, countLength: 8), 1)
        XCTAssertEqual(BeatLaneGeometry.eightOfPhrase(phrasePosition: 9, countLength: 8), 2)
        XCTAssertEqual(BeatLaneGeometry.eightOfPhrase(phrasePosition: 25, countLength: 8), 4)
        XCTAssertEqual(BeatLaneGeometry.eightOfPhrase(phrasePosition: 32, countLength: 8), 4)
    }

    // MARK: - Visible window

    func testVisibleIndicesLookFurtherAheadThanBehind() {
        // Now = 5.0s, one second back and three ahead: beats 4.0 through
        // 8.0 inclusive, i.e. indices 8 through 16.
        XCTAssertEqual(
            BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 5.0, past: 1.0, future: 3.0),
            8..<17
        )
    }

    func testVisibleIndicesClampAtTheEnds() {
        XCTAssertEqual(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 0.0, past: 1, future: 3), 0..<7)
        XCTAssertEqual(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 19.5, past: 1, future: 3), 37..<40)
    }

    func testVisibleIndicesAreEmptyOutsideTheGridOrWithoutOne() {
        XCTAssertTrue(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: 100, past: 1, future: 3).isEmpty)
        XCTAssertTrue(BeatLaneGeometry.visibleIndices(beatTimes: [], around: 1, past: 1, future: 3).isEmpty)
    }

    func testVisibleIndicesMatchABruteForceScan() {
        for now in stride(from: -1.0, through: 21.0, by: 0.37) {
            let expected = beats.indices.filter { beats[$0] >= now - 1.0 && beats[$0] <= now + 3.0 }
            let actual = Array(BeatLaneGeometry.visibleIndices(beatTimes: beats, around: now, past: 1.0, future: 3.0))
            XCTAssertEqual(actual, expected, "at \(now)")
        }
    }
}
