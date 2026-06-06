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

    // MARK: - Center of mass

    func testCenterOfMassBlendsHipAndShoulderWeightedToHip() {
        // Hips at y=200, shoulders at y=100; default hipWeight 0.65 →
        // y = 200*0.65 + 100*0.35 = 165. x is the same column so stays 50.
        let com = WeightStackingEvaluator.centerOfMass(
            leftHip: CGPoint(x: 40, y: 200),
            rightHip: CGPoint(x: 60, y: 200),
            leftShoulder: CGPoint(x: 40, y: 100),
            rightShoulder: CGPoint(x: 60, y: 100)
        )
        XCTAssertEqual(com?.x ?? -1, 50, accuracy: accuracy)
        XCTAssertEqual(com?.y ?? -1, 165, accuracy: accuracy)
    }

    func testCenterOfMassUsesHipsOnlyWhenShouldersMissing() {
        let com = WeightStackingEvaluator.centerOfMass(
            leftHip: CGPoint(x: 40, y: 200),
            rightHip: CGPoint(x: 60, y: 200),
            leftShoulder: nil,
            rightShoulder: nil
        )
        XCTAssertEqual(com?.x ?? -1, 50, accuracy: accuracy)
        XCTAssertEqual(com?.y ?? -1, 200, accuracy: accuracy)
    }

    func testCenterOfMassUsesShouldersOnlyWhenHipsMissing() {
        let com = WeightStackingEvaluator.centerOfMass(
            leftHip: nil,
            rightHip: nil,
            leftShoulder: CGPoint(x: 40, y: 100),
            rightShoulder: CGPoint(x: 60, y: 100)
        )
        XCTAssertEqual(com?.x ?? -1, 50, accuracy: accuracy)
        XCTAssertEqual(com?.y ?? -1, 100, accuracy: accuracy)
    }

    func testCenterOfMassRequiresBothJointsOfAPair() {
        // A lone hip + lone shoulder isn't enough for either midpoint.
        let com = WeightStackingEvaluator.centerOfMass(
            leftHip: CGPoint(x: 40, y: 200),
            rightHip: nil,
            leftShoulder: CGPoint(x: 40, y: 100),
            rightShoulder: nil
        )
        XCTAssertNil(com)
    }

    func testCenterOfMassNilWhenNothingAvailable() {
        XCTAssertNil(WeightStackingEvaluator.centerOfMass(
            leftHip: nil, rightHip: nil, leftShoulder: nil, rightShoulder: nil
        ))
    }

    // MARK: - CoM stacking score

    func testStackingScoreOneOverLeftAnkle() {
        let score = WeightStackingEvaluator.comStackingScore(
            comX: 100, leftAnkleX: 100, rightAnkleX: 200
        )
        XCTAssertEqual(score, 1.0, accuracy: accuracy)
    }

    func testStackingScoreOneOverRightAnkle() {
        let score = WeightStackingEvaluator.comStackingScore(
            comX: 200, leftAnkleX: 100, rightAnkleX: 200
        )
        XCTAssertEqual(score, 1.0, accuracy: accuracy)
    }

    func testStackingScoreHalfAtMidpoint() {
        // CoM dead-centre between feet → nearest ankle is half a stance away
        // → 0.5 (weight split, not stacked).
        let score = WeightStackingEvaluator.comStackingScore(
            comX: 150, leftAnkleX: 100, rightAnkleX: 200
        )
        XCTAssertEqual(score, 0.5, accuracy: accuracy)
    }

    func testStackingScoreZeroAFullStanceOutside() {
        // One stance-width beyond the right ankle.
        let score = WeightStackingEvaluator.comStackingScore(
            comX: 300, leftAnkleX: 100, rightAnkleX: 200
        )
        XCTAssertEqual(score, 0.0, accuracy: accuracy)
    }

    func testStackingScoreClampsBelowZeroWayOutside() {
        let score = WeightStackingEvaluator.comStackingScore(
            comX: 1000, leftAnkleX: 100, rightAnkleX: 200
        )
        XCTAssertEqual(score, 0.0, accuracy: accuracy)
    }

    func testStackingScoreFeetTogetherUsesMinStanceFloor() {
        // Ankles coincide; minStance floors the denominator so we don't
        // divide by zero. CoM exactly on the foot → 1.
        let onFoot = WeightStackingEvaluator.comStackingScore(
            comX: 100, leftAnkleX: 100, rightAnkleX: 100, minStance: 10
        )
        XCTAssertEqual(onFoot, 1.0, accuracy: accuracy)
        // Off by a full floor → 0.
        let offFoot = WeightStackingEvaluator.comStackingScore(
            comX: 110, leftAnkleX: 100, rightAnkleX: 100, minStance: 10
        )
        XCTAssertEqual(offFoot, 0.0, accuracy: accuracy)
    }
}
