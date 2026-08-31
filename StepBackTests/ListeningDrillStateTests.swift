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

    // MARK: - Finishing

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
