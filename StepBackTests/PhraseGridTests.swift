@testable import StepBack
import XCTest

final class PhraseGridTests: XCTestCase {

    /// 16 beats at 0.5s spacing — a tidy 120 BPM grid, indices 0...15.
    private let beats: [Double] = (0..<16).map { Double($0) * 0.5 }

    // MARK: - phraseStartTimes

    func testPhraseStartsRequireAnAnchor() {
        XCTAssertTrue(
            PhraseGrid.phraseStartTimes(
                beatTimes: beats, anchor: nil, phraseLength: 4
            ).isEmpty
        )
    }

    func testPhraseStartsAreEmptyWithoutBeats() {
        XCTAssertTrue(
            PhraseGrid.phraseStartTimes(
                beatTimes: [], anchor: 0, phraseLength: 4
            ).isEmpty
        )
    }

    func testPhraseStartsEveryNthBeatFromAnchor() {
        // Anchor at beat 0, stride 4 → indices 0, 4, 8, 12.
        XCTAssertEqual(
            PhraseGrid.phraseStartTimes(beatTimes: beats, anchor: 0, phraseLength: 4),
            [0.0, 2.0, 4.0, 6.0]
        )
    }

    func testPhraseStartsWalkBackwardsFromAnchor() {
        // Anchor mid-grid at 2.0 (index 4) — the walk must reach index 0 too.
        XCTAssertEqual(
            PhraseGrid.phraseStartTimes(beatTimes: beats, anchor: 2.0, phraseLength: 4),
            [0.0, 2.0, 4.0, 6.0]
        )
    }

    func testPhraseStartsAreSortedAscending() {
        // downbeatIndices returns a Set; the ordering is ours to guarantee.
        let starts = PhraseGrid.phraseStartTimes(
            beatTimes: beats, anchor: 3.0, phraseLength: 2
        )
        XCTAssertEqual(starts, starts.sorted())
    }

    func testLongPhraseYieldsSingleStartWhenGridIsShort() {
        // 16 beats can't contain two 32-count phrases.
        XCTAssertEqual(
            PhraseGrid.phraseStartTimes(beatTimes: beats, anchor: 0, phraseLength: 32),
            [0.0]
        )
    }

    // MARK: - Windowing

    func testWindowedPhraseStartsDropAnythingOutsideTheRange() {
        // The drill only played 1.5s...5.0s, so phrases at 0.0 and 6.0
        // must not be scored — they were never heard.
        XCTAssertEqual(
            PhraseGrid.phraseStartTimes(
                beatTimes: beats, anchor: 0, phraseLength: 4, in: 1.5...5.0
            ),
            [2.0, 4.0]
        )
    }

    func testWindowBoundsAreInclusive() {
        XCTAssertEqual(
            PhraseGrid.phraseStartTimes(
                beatTimes: beats, anchor: 0, phraseLength: 4, in: 2.0...4.0
            ),
            [2.0, 4.0]
        )
    }

    // MARK: - phrasePosition

    func testPhrasePositionIsOneIndexed() {
        XCTAssertEqual(
            PhraseGrid.phrasePosition(
                currentTime: 0.0, beatTimes: beats, anchor: 0, phraseLength: 4
            ),
            1
        )
        XCTAssertEqual(
            PhraseGrid.phrasePosition(
                currentTime: 1.5, beatTimes: beats, anchor: 0, phraseLength: 4
            ),
            4
        )
    }

    func testPhrasePositionWrapsAtTheNextPhrase() {
        XCTAssertEqual(
            PhraseGrid.phrasePosition(
                currentTime: 2.0, beatTimes: beats, anchor: 0, phraseLength: 4
            ),
            1
        )
    }

    func testPhrasePositionNilWithoutAnchor() {
        XCTAssertNil(
            PhraseGrid.phrasePosition(
                currentTime: 1.0, beatTimes: beats, anchor: nil, phraseLength: 4
            )
        )
    }

    // MARK: - toleranceSeconds

    func testToleranceScalesWithTempo() {
        // 120 BPM → 0.5s beat → 40% = 0.2s.
        XCTAssertEqual(
            PhraseGrid.toleranceSeconds(bpm: 120, fractionOfBeat: 0.4), 0.2, accuracy: 1e-9
        )
        // Half the tempo, twice the window.
        XCTAssertEqual(
            PhraseGrid.toleranceSeconds(bpm: 60, fractionOfBeat: 0.4), 0.4, accuracy: 1e-9
        )
    }

    func testToleranceIsZeroForNonsenseInput() {
        XCTAssertEqual(PhraseGrid.toleranceSeconds(bpm: 0), 0)
        XCTAssertEqual(PhraseGrid.toleranceSeconds(bpm: 120, fractionOfBeat: 0), 0)
    }

    // MARK: - score

    private let starts: [Double] = [0.0, 2.0, 4.0, 6.0]

    func testPerfectRunIsAllHits() {
        let score = PhraseGrid.score(taps: starts, phraseStarts: starts, toleranceSeconds: 0.2)
        XCTAssertEqual(score.hits, 4)
        XCTAssertEqual(score.misses, 0)
        XCTAssertEqual(score.falsePositives, 0)
        XCTAssertEqual(score.accuracy, 1.0, accuracy: 1e-9)
    }

    func testMissedPhrasesCountAsMisses() {
        let score = PhraseGrid.score(
            taps: [0.1, 2.1], phraseStarts: starts, toleranceSeconds: 0.2
        )
        XCTAssertEqual(score.hits, 2)
        XCTAssertEqual(score.misses, 2)
        XCTAssertEqual(score.falsePositives, 0)
        XCTAssertEqual(score.accuracy, 0.5, accuracy: 1e-9)
    }

    func testTapsNowhereNearAPhraseAreFalsePositives() {
        let score = PhraseGrid.score(
            taps: [1.0, 3.0], phraseStarts: [0.0, 2.0], toleranceSeconds: 0.2
        )
        XCTAssertEqual(score.hits, 0)
        XCTAssertEqual(score.misses, 2)
        XCTAssertEqual(score.falsePositives, 2)
        XCTAssertEqual(score.accuracy, 0)
    }

    func testDoubleTapOnOnePhraseScoresOneHitAndOneFalsePositive() {
        // Both taps are inside the window; only the nearer one gets credit,
        // and the spare must not be able to claim a later phrase.
        let score = PhraseGrid.score(
            taps: [1.95, 2.02], phraseStarts: [2.0], toleranceSeconds: 0.2
        )
        XCTAssertEqual(score.hits, 1)
        XCTAssertEqual(score.misses, 0)
        XCTAssertEqual(score.falsePositives, 1)
        XCTAssertEqual(score.offsetsMs.first ?? 0, 20, accuracy: 1e-6)
    }

    func testEachTapCanOnlyBeClaimedOnce() {
        // One tap sitting between two phrase starts must not satisfy both.
        let score = PhraseGrid.score(
            taps: [1.0], phraseStarts: [0.9, 1.1], toleranceSeconds: 0.2
        )
        XCTAssertEqual(score.hits, 1)
        XCTAssertEqual(score.misses, 1)
        XCTAssertEqual(score.falsePositives, 0)
    }

    func testWindowIsInclusiveAtExactlyTolerance() {
        let hit = PhraseGrid.score(
            taps: [2.2], phraseStarts: [2.0], toleranceSeconds: 0.2
        )
        XCTAssertEqual(hit.hits, 1)

        let justOutside = PhraseGrid.score(
            taps: [2.21], phraseStarts: [2.0], toleranceSeconds: 0.2
        )
        XCTAssertEqual(justOutside.hits, 0)
        XCTAssertEqual(justOutside.misses, 1)
        XCTAssertEqual(justOutside.falsePositives, 1)
    }

    func testZeroToleranceFailsEverythingRatherThanCrashing() {
        let score = PhraseGrid.score(
            taps: [0.0, 2.0], phraseStarts: starts, toleranceSeconds: 0
        )
        XCTAssertEqual(score.hits, 0)
        XCTAssertEqual(score.misses, 4)
        XCTAssertEqual(score.falsePositives, 2)
    }

    func testNoTapsMeansAllMissesAndNoFalsePositives() {
        let score = PhraseGrid.score(taps: [], phraseStarts: starts, toleranceSeconds: 0.2)
        XCTAssertEqual(score.hits, 0)
        XCTAssertEqual(score.misses, 4)
        XCTAssertEqual(score.falsePositives, 0)
    }

    // MARK: - PhraseScore

    func testEmptyScoreReadsAsZeroPercentNotFull() {
        XCTAssertEqual(PhraseScore().accuracy, 0)
        XCTAssertNil(PhraseScore().averageOffsetMs)
    }

    func testAverageOffsetIsSignedMean() {
        // Consistently late by 60ms on average.
        let score = PhraseGrid.score(
            taps: [0.05, 2.05, 4.08], phraseStarts: [0.0, 2.0, 4.0], toleranceSeconds: 0.2
        )
        XCTAssertEqual(score.averageOffsetMs ?? 0, 60, accuracy: 1e-6)
    }

    func testEarlyTapsProduceNegativeOffsets() {
        let score = PhraseGrid.score(
            taps: [1.9], phraseStarts: [2.0], toleranceSeconds: 0.2
        )
        XCTAssertEqual(score.offsetsMs.first ?? 0, -100, accuracy: 1e-6)
    }
}
