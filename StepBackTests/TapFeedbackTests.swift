@testable import StepBack
import XCTest

/// Per-tap feedback: what a single tap earns the moment it lands.
final class TapFeedbackTests: XCTestCase {

    private let targets: [Double] = [2.0, 2.5, 3.0, 3.5]

    func testOffsetIsSignedToTheNearestTarget() {
        let late = PhraseGrid.feedback(forTap: 2.53, targets: targets, toleranceSeconds: 0.2)
        XCTAssertEqual(late?.offsetMs ?? 0, 30, accuracy: 1e-6)

        let early = PhraseGrid.feedback(forTap: 2.96, targets: targets, toleranceSeconds: 0.2)
        XCTAssertEqual(early?.offsetMs ?? 0, -40, accuracy: 1e-6)
    }

    func testHitIsInclusiveAtExactlyTheTolerance() {
        XCTAssertEqual(
            PhraseGrid.feedback(forTap: 2.2, targets: targets, toleranceSeconds: 0.2)?.isHit,
            true
        )
        XCTAssertEqual(
            PhraseGrid.feedback(forTap: 2.21, targets: targets, toleranceSeconds: 0.2)?.isHit,
            false
        )
    }

    func testRatingFollowsTheStepTimingBuckets() {
        XCTAssertEqual(
            PhraseGrid.feedback(forTap: 2.02, targets: targets, toleranceSeconds: 0.25)?.rating,
            .perfect
        )
        XCTAssertEqual(
            PhraseGrid.feedback(forTap: 2.08, targets: targets, toleranceSeconds: 0.25)?.rating,
            .good
        )
        XCTAssertEqual(
            PhraseGrid.feedback(forTap: 2.2, targets: targets, toleranceSeconds: 0.25)?.rating,
            .off
        )
    }

    func testStrayTapStillReportsHowFarFromTheNearestTarget() {
        // A tap in no-man's-land is a miss, but the dancer still learns
        // which side of the nearest 1 they landed on.
        let stray = PhraseGrid.feedback(forTap: 2.26, targets: targets, toleranceSeconds: 0.1)
        XCTAssertEqual(stray?.isHit, false)
        XCTAssertEqual(stray?.offsetMs ?? 0, -240, accuracy: 1e-6)
    }

    func testNoTargetsMeansNoFeedback() {
        XCTAssertNil(PhraseGrid.feedback(forTap: 1.0, targets: [], toleranceSeconds: 0.2))
    }
}
