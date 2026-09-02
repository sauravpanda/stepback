@testable import StepBack
import XCTest

final class ListeningDrillPlanTests: XCTestCase {

    /// Six phrases, four seconds apart.
    private let phrases: [Double] = [0, 4, 8, 12, 16, 20]

    private func shape(
        lead: Int = 1,
        scored: Int = 3,
        tolerance: Double = 0.2
    ) -> DrillShape {
        DrillShape(leadPhrases: lead, scoredPhrases: scored, toleranceSeconds: tolerance)
    }

    // MARK: - DrillShape

    func testShapeClampsNonsenseToUsableValues() {
        let clamped = DrillShape(leadPhrases: 0, scoredPhrases: 0, toleranceSeconds: -1)
        XCTAssertEqual(clamped.leadPhrases, 1)
        XCTAssertEqual(clamped.scoredPhrases, 1)
        XCTAssertEqual(clamped.toleranceSeconds, 0)
    }

    // MARK: - startIndices

    func testStartIndicesLeaveRoomForTheLeadIn() {
        XCTAssertEqual(
            ListeningDrillPlanner.startIndices(phraseCount: 6, leadPhrases: 1), 0..<5
        )
        XCTAssertEqual(
            ListeningDrillPlanner.startIndices(phraseCount: 6, leadPhrases: 2), 0..<4
        )
    }

    func testStartIndicesEmptyWhenClipTooShort() {
        XCTAssertTrue(
            ListeningDrillPlanner.startIndices(phraseCount: 1, leadPhrases: 1).isEmpty
        )
        XCTAssertTrue(
            ListeningDrillPlanner.startIndices(phraseCount: 0, leadPhrases: 1).isEmpty
        )
    }

    // MARK: - plan

    func testPlanStartsOnAPhraseAndScoresTheFollowingOnes() throws {
        let plan = try XCTUnwrap(
            ListeningDrillPlanner.plan(
                phraseStarts: phrases, startIndex: 0, shape: shape(), duration: 100
            )
        )
        XCTAssertEqual(plan.playbackStart, 0)
        XCTAssertEqual(plan.scoredStarts, [4, 8, 12])
        // The first scored phrase is exactly where the counter goes dark.
        XCTAssertEqual(plan.revealUntil, 4)
    }

    func testLongerLeadInPushesScoringLater() {
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 0, shape: shape(lead: 2), duration: 100
        )
        XCTAssertEqual(plan?.playbackStart, 0)
        XCTAssertEqual(plan?.scoredStarts, [8, 12, 16])
        XCTAssertEqual(plan?.revealUntil, 8)
    }

    func testEndTimeLeavesRoomToTapThePhraseLate() {
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 0, shape: shape(), duration: 100
        )
        // Last scored phrase 12 + 0.2 tolerance + 0.25 padding.
        XCTAssertEqual(plan?.endTime ?? 0, 12.45, accuracy: 1e-9)
    }

    func testEndTimeNeverRunsPastTheClip() {
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 0, shape: shape(), duration: 10
        )
        XCTAssertEqual(plan?.endTime, 10)
    }

    func testPlanTakesWhateverPhrasesRemainNearTheEnd() {
        // Only one phrase left after the lead-in; the take shortens rather
        // than failing.
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 4, shape: shape(), duration: 100
        )
        XCTAssertEqual(plan?.scoredStarts, [20])
    }

    func testPlanRejectsAStartWithNothingLeftToScore() {
        XCTAssertNil(
            ListeningDrillPlanner.plan(
                phraseStarts: phrases, startIndex: 5, shape: shape(), duration: 100
            )
        )
    }

    func testPlanRejectsAClipWithTooFewPhrases() {
        XCTAssertNil(
            ListeningDrillPlanner.plan(
                phraseStarts: [0], startIndex: 0, shape: shape(), duration: 100
            )
        )
    }

    // MARK: - Every-beat targets

    /// Half-second beats under the four-second phrases.
    private let beats: [Double] = (0..<48).map { Double($0) * 0.5 }

    private func everyBeat(scored: Int = 2) -> DrillShape {
        DrillShape(leadPhrases: 1, scoredPhrases: scored, toleranceSeconds: 0.2, gradesEveryBeat: true)
    }

    func testTargetsAreThePhraseStartsUnlessAskedForEveryBeat() {
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 0, shape: shape(), duration: 100, beatTimes: beats
        )
        XCTAssertEqual(plan?.targets, plan?.scoredStarts)
    }

    func testEveryBeatTargetsCoverTheScoredPhrasesOnly() {
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 0, shape: everyBeat(), duration: 100, beatTimes: beats
        )
        // Scored phrases start at 4 and 8; the window runs up to the phrase
        // at 12, exclusive — sixteen beats.
        XCTAssertEqual(plan?.scoredStarts, [4, 8])
        XCTAssertEqual(plan?.targets, (8..<24).map { Double($0) * 0.5 })
        // The take ends after the last *beat*, not the last phrase start.
        XCTAssertEqual(plan?.endTime ?? 0, 11.5 + 0.2 + 0.25, accuracy: 1e-9)
    }

    func testEveryBeatWindowRunsToTheClipWhenNoPhraseFollows() {
        // Start at 3: scored 16 and 20, nothing after 20, so the window
        // ends at the clip.
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 3, shape: everyBeat(scored: 3), duration: 22, beatTimes: beats
        )
        XCTAssertEqual(plan?.targets, (32..<44).map { Double($0) * 0.5 })
    }

    func testEveryBeatFallsBackToPhraseStartsWithoutAGrid() {
        let plan = ListeningDrillPlanner.plan(
            phraseStarts: phrases, startIndex: 0, shape: everyBeat(), duration: 100, beatTimes: []
        )
        XCTAssertEqual(plan?.targets, [4, 8])
    }

    func testRandomPlanIsNilWhenNoStartIsViable() {
        XCTAssertNil(
            ListeningDrillPlanner.randomPlan(
                phraseStarts: [0], shape: shape(), duration: 100
            )
        )
    }

    func testRandomPlanAlwaysLandsOnAValidPhrase() {
        for _ in 0..<25 {
            let plan = ListeningDrillPlanner.randomPlan(
                phraseStarts: phrases, shape: shape(), duration: 100
            )
            let start = plan?.playbackStart ?? -1
            XCTAssertTrue(phrases.contains(start), "start \(start) is not a phrase boundary")
            XCTAssertFalse(plan?.scoredStarts.isEmpty ?? true)
        }
    }
}
