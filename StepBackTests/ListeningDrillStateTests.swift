@testable import StepBack
import XCTest

final class ListeningDrillStateTests: XCTestCase {

    private let plan = ListeningDrillPlan(
        playbackStart: 0,
        scoredStarts: [4, 8, 12],
        revealUntil: 4,
        endTime: 12.45
    )

    // MARK: - Initial state

    func testStartsIdleWithNothingToShow() {
        let state = ListeningDrillState()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.plan)
        XCTAssertNil(state.score)
        XCTAssertNil(state.oneShot)
        XCTAssertNil(state.planError)
        XCTAssertTrue(state.taps.isEmpty)
    }

    // MARK: - Beginning a take

    func testBeginEntersRunningWithThePlan() {
        var state = ListeningDrillState()
        state.begin(plan: plan)
        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(state.plan, plan)
    }

    func testBeginClearsThePreviousResult() {
        // A stale score must never be on screen next to a live run.
        var state = ListeningDrillState()
        state.begin(plan: plan)
        state.recordTap(at: 4)
        state.finish(toleranceSeconds: 0.2)
        XCTAssertNotNil(state.score)

        state.begin(plan: plan)
        XCTAssertNil(state.score)
        XCTAssertTrue(state.taps.isEmpty)
        XCTAssertEqual(state.phase, .running)
    }

    func testOpenEndedTakeRunsWithoutAPlan() {
        var state = ListeningDrillState()
        state.beginOpenEnded()
        XCTAssertEqual(state.phase, .running)
        XCTAssertNil(state.plan)
    }

    // MARK: - Taps

    func testTapsAreOnlyCollectedWhileRunning() {
        var state = ListeningDrillState()
        state.recordTap(at: 1)
        XCTAssertTrue(state.taps.isEmpty, "idle drill must ignore taps")

        state.begin(plan: plan)
        state.recordTap(at: 4)
        XCTAssertEqual(state.taps, [4])

        state.finish(toleranceSeconds: 0.2)
        state.recordTap(at: 9)
        XCTAssertEqual(state.taps, [4], "finished drill must ignore taps")
    }

    func testRecordTapKeepsTheLatestFeedback() {
        var state = ListeningDrillState()
        state.begin(plan: plan)
        XCTAssertNil(state.lastFeedback)

        let first = TapFeedback(offsetMs: 30, isHit: true)
        state.recordTap(at: 4.03, feedback: first)
        XCTAssertEqual(state.lastFeedback, first)

        let second = TapFeedback(offsetMs: -300, isHit: false)
        state.recordTap(at: 7.7, feedback: second)
        XCTAssertEqual(state.lastFeedback, second)
        XCTAssertEqual(state.taps, [4.03, 7.7])
    }

    func testBeginClearsTheLastFeedback() {
        var state = ListeningDrillState()
        state.begin(plan: plan)
        state.recordTap(at: 4, feedback: TapFeedback(offsetMs: 0, isHit: true))
        state.finish(toleranceSeconds: 0.2)

        state.begin(plan: plan)
        XCTAssertNil(state.lastFeedback, "feedback from the last take must not greet the new one")
    }

    // MARK: - Finishing

    func testFinishGradesAgainstTheTargetsNotThePhraseStarts() {
        // Tap the Beat: two phrases, every beat a target.
        let everyBeat = ListeningDrillPlan(
            playbackStart: 0,
            scoredStarts: [4, 8],
            targets: [4, 5, 6, 7, 8, 9, 10, 11],
            revealUntil: 4,
            endTime: 11.45
        )
        var state = ListeningDrillState()
        state.begin(plan: everyBeat)
        for beat in [4.0, 5.1, 6.0, 7.0, 8.0, 9.0] {
            state.recordTap(at: beat)
        }
        state.finish(toleranceSeconds: 0.2)

        XCTAssertEqual(state.score?.hits, 6)
        XCTAssertEqual(state.score?.misses, 2)
        XCTAssertEqual(state.score?.falsePositives, 0)
    }

    func testFinishGradesAgainstThePlan() {
        var state = ListeningDrillState()
        state.begin(plan: plan)
        state.recordTap(at: 4.05)
        state.recordTap(at: 8.0)
        state.finish(toleranceSeconds: 0.2)

        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.score?.hits, 2)
        XCTAssertEqual(state.score?.misses, 1)
        XCTAssertEqual(state.score?.falsePositives, 0)
    }

    func testFinishDoesNothingWithoutARunningPlan() {
        var state = ListeningDrillState()
        state.finish(toleranceSeconds: 0.2)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.score)
    }

    func testAnswerEndsAnOpenEndedTake() {
        var state = ListeningDrillState()
        state.beginOpenEnded()
        state.answer(FindTheOneResult(offsetMs: -30, measurePosition: 1))

        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.oneShot?.landedOnOne, true)
        XCTAssertEqual(state.oneShot?.rating, .perfect)
    }

    func testAnswerIsIgnoredWhenNotRunning() {
        var state = ListeningDrillState()
        state.answer(FindTheOneResult(offsetMs: 0, measurePosition: 1))
        XCTAssertNil(state.oneShot)
        XCTAssertEqual(state.phase, .idle)
    }

    // MARK: - Ribbon

    func testSlotStatesColourEachTargetByItsNearestTap() {
        var state = ListeningDrillState()
        state.begin(plan: plan)
        state.recordTap(at: 4.03)
        state.recordTap(at: 8.1)

        XCTAssertEqual(
            state.slotStates(at: 9.0, toleranceSeconds: 0.2),
            [.hit(.perfect), .hit(.good), .pending]
        )
        // Once the window on 12 has closed with no tap, it's a miss.
        XCTAssertEqual(state.slotStates(at: 12.5, toleranceSeconds: 0.2).last, .missed)
    }

    func testSlotStatesReadTheNearestTapSoADoubleTapColoursOneCell() {
        var state = ListeningDrillState()
        state.begin(plan: plan)
        state.recordTap(at: 3.96)
        state.recordTap(at: 4.15)
        XCTAssertEqual(
            state.slotStates(at: 5, toleranceSeconds: 0.2).first,
            .hit(.perfect),
            "the closer tap (−40ms) wins over the stray second one"
        )
    }

    func testSlotStatesAreEmptyWithoutAPlan() {
        XCTAssertEqual(ListeningDrillState().slotStates(at: 0, toleranceSeconds: 0.2), [])
    }

    // MARK: - Running out

    func testHasRunOutOnlyOnceThePlanEndPasses() {
        var state = ListeningDrillState()
        XCTAssertFalse(state.hasRunOut(at: 999), "idle drill can't run out")

        state.begin(plan: plan)
        XCTAssertFalse(state.hasRunOut(at: 12.0))
        XCTAssertTrue(state.hasRunOut(at: 12.45))
        XCTAssertTrue(state.hasRunOut(at: 13.0))
    }

    func testOpenEndedTakeNeverRunsOutOnItsOwn() {
        var state = ListeningDrillState()
        state.beginOpenEnded()
        XCTAssertFalse(state.hasRunOut(at: 9_999))
    }

    // MARK: - Failure

    func testFailReportsAndClearsTheRun() {
        var state = ListeningDrillState()
        state.begin(plan: plan)
        state.recordTap(at: 4)
        state.fail("too short")

        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.planError, "too short")
        XCTAssertNil(state.plan)
        XCTAssertTrue(state.taps.isEmpty)
    }

    func testResetClearsEverythingIncludingTheError() {
        var state = ListeningDrillState()
        state.fail("too short")
        state.reset()
        XCTAssertNil(state.planError)
        XCTAssertEqual(state, ListeningDrillState())
    }
}
