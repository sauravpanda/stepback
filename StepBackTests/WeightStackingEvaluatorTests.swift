@testable import StepBack
import CoreGraphics
import XCTest

final class WeightStackingEvaluatorTests: XCTestCase {

    private let accuracy: Double = 0.001

    // MARK: - Vertical axis

    func testVerticalBoneScoresOneWhenPerfectlyVertical() {
        // Straight down. View coords: positive y is down.
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 100, y: 300),
            axis: .vertical
        )
        XCTAssertEqual(score, 1.0, accuracy: accuracy)
    }

    func testVerticalBoneScoresOneWhenPerfectlyUpward() {
        // Bone direction sign shouldn't matter — abs of dy.
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 100, y: 300),
            to: CGPoint(x: 100, y: 100),
            axis: .vertical
        )
        XCTAssertEqual(score, 1.0, accuracy: accuracy)
    }

    func testVerticalBoneScoresZeroAtForty5Degrees() {
        // dx = dy = 100, angle from vertical = 45°.
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 100),
            axis: .vertical
        )
        XCTAssertEqual(score, 0.0, accuracy: accuracy)
    }

    func testVerticalBoneScoresZeroBeyondForty5Degrees() {
        // 30°/60° triangle — well past the 45° threshold (angle from
        // vertical = 60°), so score is clamped to 0.
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 57.735),  // tan(30°) = 0.577…
            axis: .vertical
        )
        XCTAssertEqual(score, 0.0, accuracy: accuracy)
    }

    func testVerticalBoneScoresHalfAtTwentyTwoPointFiveDegrees() {
        // 22.5° off vertical → score = 1 - 22.5/45 = 0.5
        let angle = 22.5 * .pi / 180
        let dx = sin(angle) * 100
        let dy = cos(angle) * 100
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: dx, y: dy),
            axis: .vertical
        )
        XCTAssertEqual(score, 0.5, accuracy: accuracy)
    }

    // MARK: - Horizontal axis

    func testHorizontalBoneScoresOneWhenPerfectlyHorizontal() {
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 0, y: 100),
            to: CGPoint(x: 200, y: 100),
            axis: .horizontal
        )
        XCTAssertEqual(score, 1.0, accuracy: accuracy)
    }

    func testHorizontalBoneScoresZeroAtForty5Degrees() {
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 100),
            axis: .horizontal
        )
        XCTAssertEqual(score, 0.0, accuracy: accuracy)
    }

    func testHorizontalBoneScoresZeroWhenVertical() {
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 100, y: 0),
            to: CGPoint(x: 100, y: 200),
            axis: .horizontal
        )
        XCTAssertEqual(score, 0.0, accuracy: accuracy)
    }

    // MARK: - Neutral axis

    func testNeutralBoneAlwaysScoresOne() {
        // Same diagonal that scored 0 for vertical and horizontal.
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 100),
            axis: .neutral
        )
        XCTAssertEqual(score, 1.0, accuracy: accuracy)
    }

    // MARK: - Degenerate input

    func testZeroLengthBoneReturnsOne() {
        // Same point for start and end — no meaningful direction to score.
        // Prefer "fine" over NaN or 0 so the overlay doesn't flash red on
        // a transient bad detection.
        let score = WeightStackingEvaluator.alignmentScore(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 100, y: 100),
            axis: .vertical
        )
        XCTAssertEqual(score, 1.0, accuracy: accuracy)
    }
}
