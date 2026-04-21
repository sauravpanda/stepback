@testable import StepBack
import XCTest

final class BeatGridTests: XCTestCase {

    private let beats = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]

    // MARK: - nearestBeatIndex

    func testNearestBeatOnEmptyReturnsNil() {
        XCTAssertNil(BeatGrid.nearestBeatIndex(to: 1.0, in: []))
    }

    func testNearestBeatExactHit() {
        XCTAssertEqual(BeatGrid.nearestBeatIndex(to: 2.0, in: beats), 3)
    }

    func testNearestBeatBetweenPrefersCloser() {
        // 1.7 is 0.2 past 1.5, 0.3 before 2.0 → nearest is 1.5 (index 2)
        XCTAssertEqual(BeatGrid.nearestBeatIndex(to: 1.7, in: beats), 2)
        // 1.8 is 0.3 past 1.5, 0.2 before 2.0 → nearest is 2.0 (index 3)
        XCTAssertEqual(BeatGrid.nearestBeatIndex(to: 1.8, in: beats), 3)
    }

    func testNearestBeatBeforeFirstAndAfterLast() {
        XCTAssertEqual(BeatGrid.nearestBeatIndex(to: 0.0, in: beats), 0)
        XCTAssertEqual(BeatGrid.nearestBeatIndex(to: 99.0, in: beats), beats.count - 1)
    }

    // MARK: - offsetMs

    func testOffsetMsEarly() {
        // Tap at 1.45, nearest is 1.5 → -50ms (early)
        XCTAssertEqual(BeatGrid.offsetMs(from: 1.45, toNearestBeatIn: beats) ?? 0, -50, accuracy: 1e-6)
    }

    func testOffsetMsLate() {
        // Tap at 1.55, nearest is 1.5 → +50ms (late)
        XCTAssertEqual(BeatGrid.offsetMs(from: 1.55, toNearestBeatIn: beats) ?? 0, 50, accuracy: 1e-6)
    }

    // MARK: - downbeatIndices

    func testDownbeatIndicesRequiresAnchor() {
        XCTAssertTrue(
            BeatGrid.downbeatIndices(beatTimes: beats, anchor: nil, beatsPerMeasure: 4).isEmpty
        )
    }

    func testDownbeatIndicesEveryNthBeat() {
        // Anchor at 1.0 (index 1). With beatsPerMeasure = 4, downbeats at
        // indices {1, 5} (wrap backwards would hit -3, out of range).
        let indices = BeatGrid.downbeatIndices(
            beatTimes: beats, anchor: 1.0, beatsPerMeasure: 4
        )
        XCTAssertEqual(indices, [1, 5])
    }

    func testDownbeatIndicesIncludesBackwardsFromAnchor() {
        // Anchor at 2.5 (index 4). With bpm = 2, downbeats at {0, 2, 4, 6}.
        let indices = BeatGrid.downbeatIndices(
            beatTimes: beats, anchor: 2.5, beatsPerMeasure: 2
        )
        XCTAssertEqual(indices, [0, 2, 4, 6])
    }

    // MARK: - currentMeasurePosition

    func testMeasurePositionIsOneAtAnchor() {
        let position = BeatGrid.currentMeasurePosition(
            currentTime: 1.0, beatTimes: beats, anchor: 1.0, beatsPerMeasure: 4
        )
        XCTAssertEqual(position, 1)
    }

    func testMeasurePositionAdvancesAcrossBeats() {
        // Anchor at 1.0 (index 1). currentTime 1.5 (index 2) → position 2.
        XCTAssertEqual(
            BeatGrid.currentMeasurePosition(
                currentTime: 1.5, beatTimes: beats, anchor: 1.0, beatsPerMeasure: 4
            ),
            2
        )
        XCTAssertEqual(
            BeatGrid.currentMeasurePosition(
                currentTime: 2.0, beatTimes: beats, anchor: 1.0, beatsPerMeasure: 4
            ),
            3
        )
        XCTAssertEqual(
            BeatGrid.currentMeasurePosition(
                currentTime: 2.5, beatTimes: beats, anchor: 1.0, beatsPerMeasure: 4
            ),
            4
        )
        // Back to 1 on the next measure.
        XCTAssertEqual(
            BeatGrid.currentMeasurePosition(
                currentTime: 3.0, beatTimes: beats, anchor: 1.0, beatsPerMeasure: 4
            ),
            1
        )
    }

    func testMeasurePositionBeforeAnchorWrapsCleanly() {
        // Anchor at 2.5 (index 4). currentTime 1.0 (index 1) → -3 mod 4 = 1 → position 2.
        XCTAssertEqual(
            BeatGrid.currentMeasurePosition(
                currentTime: 1.0, beatTimes: beats, anchor: 2.5, beatsPerMeasure: 4
            ),
            2
        )
    }

    // MARK: - rescale

    func testRescaleDoubleInsertsMidpoints() {
        let input = [0.0, 0.5, 1.0]
        XCTAssertEqual(BeatGrid.rescale(beatTimes: input, factor: 2), [0, 0.25, 0.5, 0.75, 1.0])
    }

    func testRescaleHalveKeepsEveryOther() {
        let input = [0.0, 0.25, 0.5, 0.75, 1.0]
        XCTAssertEqual(BeatGrid.rescale(beatTimes: input, factor: 0.5), [0, 0.5, 1.0])
    }

    func testRescaleIdentityForOtherFactors() {
        let input = [0.0, 0.5, 1.0]
        XCTAssertEqual(BeatGrid.rescale(beatTimes: input, factor: 3), input)
    }

    func testRescaleShortInputUnchanged() {
        XCTAssertEqual(BeatGrid.rescale(beatTimes: [], factor: 2), [])
        XCTAssertEqual(BeatGrid.rescale(beatTimes: [1.0], factor: 2), [1.0])
    }
}
