@testable import StepBack
import XCTest

final class CountSubdivisionTests: XCTestCase {

    /// Beats one second apart, so a slot boundary lands on a tidy fraction.
    private let beats: [Double] = [0, 1, 2, 3]

    // MARK: - Shape

    func testSlotCountsPerBeat() {
        XCTAssertEqual(CountSubdivision.quarter.perBeat, 1)
        XCTAssertEqual(CountSubdivision.eighth.perBeat, 2)
        XCTAssertEqual(CountSubdivision.swung.perBeat, 3)
        XCTAssertEqual(CountSubdivision.triplet.perBeat, 3)
        XCTAssertEqual(CountSubdivision.sixteenth.perBeat, 4)
    }

    func testOnlySwungHasASilentSlot() {
        XCTAssertEqual(CountSubdivision.swung.silentSlots, [1])
        XCTAssertEqual(CountSubdivision.swung.stepSlot, 2)
        for other in CountSubdivision.allCases where other != .swung {
            XCTAssertTrue(other.silentSlots.isEmpty, "\(other.rawValue) clicks every slot")
            XCTAssertNil(other.stepSlot)
        }
    }

    // MARK: - subdivisionIndex

    func testIndexWalksTheSlotsAcrossOneBeat() {
        // Quarter of the way through the beat is slot 1 of 4, and so on.
        let slots = [0.0, 0.25, 0.5, 0.75].map {
            PhraseGrid.subdivisionIndex(currentTime: $0, beatTimes: beats, perBeat: 4)
        }
        XCTAssertEqual(slots, [0, 1, 2, 3])
    }

    func testIndexResetsOnTheNextBeat() {
        XCTAssertEqual(
            PhraseGrid.subdivisionIndex(currentTime: 1.0, beatTimes: beats, perBeat: 4), 0
        )
        XCTAssertEqual(
            PhraseGrid.subdivisionIndex(currentTime: 1.5, beatTimes: beats, perBeat: 2), 1
        )
    }

    func testIndexIsZeroForPlainQuarterCounting() {
        XCTAssertEqual(
            PhraseGrid.subdivisionIndex(currentTime: 0.9, beatTimes: beats, perBeat: 1), 0
        )
    }

    func testIndexHoldsOnTheLastBeat() {
        // No following beat means no interval to divide — better to sit on
        // the beat than to invent a spacing.
        XCTAssertEqual(
            PhraseGrid.subdivisionIndex(currentTime: 3.4, beatTimes: beats, perBeat: 4), 0
        )
    }

    func testIndexNilBeforeTheFirstBeat() {
        XCTAssertNil(
            PhraseGrid.subdivisionIndex(currentTime: -0.5, beatTimes: beats, perBeat: 4)
        )
    }

    func testIndexNilWithoutAGrid() {
        XCTAssertNil(PhraseGrid.subdivisionIndex(currentTime: 1, beatTimes: [], perBeat: 4))
        XCTAssertNil(PhraseGrid.subdivisionIndex(currentTime: 1, beatTimes: [0], perBeat: 4))
    }

    func testIndexTracksUnevenBeatSpacing() {
        // Grids come from onset alignment, not a metronome, so slots have to
        // follow the actual interval rather than an assumed one.
        let uneven: [Double] = [0, 2, 3]
        XCTAssertEqual(
            PhraseGrid.subdivisionIndex(currentTime: 1.0, beatTimes: uneven, perBeat: 2), 1
        )
        XCTAssertEqual(
            PhraseGrid.subdivisionIndex(currentTime: 2.4, beatTimes: uneven, perBeat: 2), 0
        )
    }

    // MARK: - subdivide

    func testSubdivideInsertsEvenlySpacedSlots() {
        XCTAssertEqual(
            PhraseGrid.subdivide(beatTimes: [0, 1], perBeat: 4),
            [0, 0.25, 0.5, 0.75, 1]
        )
    }

    func testSubdivideHandlesTriplets() {
        let result = PhraseGrid.subdivide(beatTimes: [0, 3], perBeat: 3)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[1], 1, accuracy: 1e-9)
        XCTAssertEqual(result[2], 2, accuracy: 1e-9)
    }

    func testSubdivideLeavesQuartersAlone() {
        XCTAssertEqual(PhraseGrid.subdivide(beatTimes: beats, perBeat: 1), beats)
    }

    func testSubdivideFollowsUnevenSpacing() {
        XCTAssertEqual(
            PhraseGrid.subdivide(beatTimes: [0, 2, 3], perBeat: 2),
            [0, 1, 2, 2.5, 3]
        )
    }

    func testSubdivideKeepsEveryOriginalBeat() {
        let result = PhraseGrid.subdivide(beatTimes: beats, perBeat: 4)
        for beat in beats {
            XCTAssertTrue(
                result.contains { abs($0 - beat) < 1e-9 },
                "original beat \(beat) must survive subdivision"
            )
        }
    }

    func testSubdivideIsSafeOnATinyGrid() {
        XCTAssertEqual(PhraseGrid.subdivide(beatTimes: [], perBeat: 4), [])
        XCTAssertEqual(PhraseGrid.subdivide(beatTimes: [1], perBeat: 4), [1])
    }

    // MARK: - clickPlan

    func testSwungClicksTheBeatAndTheLateA() {
        let plan = PhraseGrid.clickPlan(
            beatTimes: [0, 3, 6],
            subdivision: .swung,
            anchor: 0,
            beatsPerMeasure: 4
        )
        // The "&" at 1 and 4 is dropped; the "a" sits two-thirds through.
        XCTAssertEqual(plan.times, [0, 2, 3, 5, 6])
        XCTAssertEqual(plan.subdivisions, [1, 3])
        XCTAssertEqual(plan.downbeats, [0])
    }

    func testDroppingSilentSlotsKeepsDownbeatsOnTheBeat() {
        let beats = (0...8).map(Double.init)
        let plan = PhraseGrid.clickPlan(
            beatTimes: beats,
            subdivision: .swung,
            anchor: 0,
            beatsPerMeasure: 4
        )
        XCTAssertEqual(plan.downbeats.map { plan.times[$0] }.sorted(), [0, 4, 8])
    }

    func testSlotsBeforeTheAnchorKeepTheirRoles() {
        let plan = PhraseGrid.clickPlan(
            beatTimes: [0, 3, 6],
            subdivision: .swung,
            anchor: 3,
            beatsPerMeasure: 4
        )
        XCTAssertEqual(plan.times, [0, 2, 3, 5, 6])
        XCTAssertEqual(plan.subdivisions.map { plan.times[$0] }.sorted(), [2, 5])
        XCTAssertEqual(plan.downbeats.map { plan.times[$0] }, [3])
    }

    func testEvenSubdivisionsClickEverySlot() {
        let plan = PhraseGrid.clickPlan(
            beatTimes: [0, 1, 2],
            subdivision: .eighth,
            anchor: 0,
            beatsPerMeasure: 4
        )
        XCTAssertEqual(plan.times, [0, 0.5, 1, 1.5, 2])
        XCTAssertEqual(plan.subdivisions, [1, 3])
        XCTAssertEqual(plan.downbeats, [0])
    }
}
