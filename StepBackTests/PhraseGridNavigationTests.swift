@testable import StepBack
import XCTest

/// Transport-side of `PhraseGrid`: moving between phrases, bounding one for
/// looping, and nudging a guessed anchor onto the real downbeat. Split from
/// `PhraseGridTests` to keep either class inside SwiftLint's body-length
/// limit.
final class PhraseGridNavigationTests: XCTestCase {

    /// 16 beats at 0.5s spacing, so phrase starts land at 0, 2, 4, 6.
    private let beats: [Double] = (0..<16).map { Double($0) * 0.5 }

    /// Phrase starts at 0, 2, 4, 6 (stride 4 over the 0.5s grid).
    private var navAnchor: Double { 0 }

    func testNextPhraseIsStrictlyAfterNow() {
        XCTAssertEqual(
            PhraseGrid.phraseStart(
                after: 2.0, beatTimes: beats, anchor: navAnchor, phraseLength: 4
            ),
            4.0,
            "sitting exactly on a phrase start should advance, not stay put"
        )
    }

    func testNextPhraseIsNilAtTheLastOne() {
        XCTAssertNil(
            PhraseGrid.phraseStart(
                after: 6.5, beatTimes: beats, anchor: navAnchor, phraseLength: 4
            )
        )
    }

    func testPreviousPhraseRestartsTheCurrentOneWhenWellIntoIt() {
        // 3.5s is 1.5s into the phrase that began at 2.0 — past the grace,
        // so "back" means restart this phrase.
        XCTAssertEqual(
            PhraseGrid.phraseStart(
                before: 3.5, beatTimes: beats, anchor: navAnchor, phraseLength: 4
            ),
            2.0
        )
    }

    func testPreviousPhraseStepsBackWhenJustPastTheStart() {
        // 2.4s is only 0.4s into the phrase at 2.0, inside the grace window,
        // so "back" should reach the previous phrase instead.
        XCTAssertEqual(
            PhraseGrid.phraseStart(
                before: 2.4, beatTimes: beats, anchor: navAnchor, phraseLength: 4
            ),
            0.0
        )
    }

    func testPreviousPhraseFromTheFirstPhraseStaysThere() {
        XCTAssertEqual(
            PhraseGrid.phraseStart(
                before: 0.3, beatTimes: beats, anchor: navAnchor, phraseLength: 4
            ),
            0.0
        )
    }

    // MARK: - currentPhraseBounds

    func testPhraseBoundsRunToTheNextPhraseStart() {
        let bounds = PhraseGrid.currentPhraseBounds(
            at: 2.7, beatTimes: beats, anchor: navAnchor, phraseLength: 4
        )
        XCTAssertEqual(bounds?.start, 2.0)
        XCTAssertEqual(bounds?.end, 4.0)
    }

    func testConsecutivePhraseBoundsAbut() {
        // No gap and no overlap, so looping phrase after phrase is seamless.
        let first = PhraseGrid.currentPhraseBounds(
            at: 2.1, beatTimes: beats, anchor: navAnchor, phraseLength: 4
        )
        let second = PhraseGrid.currentPhraseBounds(
            at: 4.1, beatTimes: beats, anchor: navAnchor, phraseLength: 4
        )
        XCTAssertEqual(first?.end, second?.start)
    }

    func testLastPhraseBoundsFallBackToTheFinalBeat() {
        let bounds = PhraseGrid.currentPhraseBounds(
            at: 6.6, beatTimes: beats, anchor: navAnchor, phraseLength: 4
        )
        XCTAssertEqual(bounds?.start, 6.0)
        XCTAssertEqual(bounds?.end, beats.last)
    }

    func testPhraseBoundsNilWithoutAnAnchor() {
        XCTAssertNil(
            PhraseGrid.currentPhraseBounds(
                at: 2.0, beatTimes: beats, anchor: nil, phraseLength: 4
            )
        )
    }

    // MARK: - shiftAnchor

    func testShiftAnchorMovesAlongTheGrid() {
        XCTAssertEqual(PhraseGrid.shiftAnchor(2.0, byBeats: 1, in: beats), 2.5)
        XCTAssertEqual(PhraseGrid.shiftAnchor(2.0, byBeats: -1, in: beats), 1.5)
    }

    func testShiftAnchorClampsAtBothEnds() {
        XCTAssertEqual(PhraseGrid.shiftAnchor(0.0, byBeats: -5, in: beats), beats.first)
        XCTAssertEqual(PhraseGrid.shiftAnchor(7.5, byBeats: 5, in: beats), beats.last)
    }

    func testShiftAnchorNilWithoutAGrid() {
        XCTAssertNil(PhraseGrid.shiftAnchor(1.0, byBeats: 1, in: []))
    }

    func testShiftAnchorWrapsAWholePhraseRatherThanClamping() {
        // Anchor on beat 14 of 16, nudged forward one 8: off the end, so it
        // comes back a phrase (8 beats here) to beat 14 + 4 - 8 = 10, which
        // is the same count. Clamping to beat 15 would have moved "1".
        XCTAssertEqual(
            PhraseGrid.shiftAnchor(7.0, byBeats: 4, in: beats, keepingPhaseOf: 8),
            5.0
        )
        XCTAssertEqual(
            PhraseGrid.shiftAnchor(0.5, byBeats: -4, in: beats, keepingPhaseOf: 8),
            2.5
        )
        // In range: no wrap.
        XCTAssertEqual(
            PhraseGrid.shiftAnchor(2.0, byBeats: 4, in: beats, keepingPhaseOf: 8),
            4.0
        )
    }
}
