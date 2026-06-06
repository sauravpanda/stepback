@testable import StepBack
import CoreGraphics
import Vision
import XCTest

final class PoseSmootherTests: XCTestCase {

    private func pose(
        _ entries: [(VNHumanBodyPoseObservation.JointName, CGPoint)],
        confidence: Float = 0.9
    ) -> DetectedPose {
        DetectedPose(joints: entries.map { name, point in
            DetectedJoint(name: name, normalizedPosition: point, confidence: confidence)
        })
    }

    func testFirstPosePassesThroughUnchanged() {
        var smoother = PoseSmoother()
        let input = pose([(.leftWrist, CGPoint(x: 0.3, y: 0.7))])
        let output = smoother.smooth(input, timestamp: 0)
        let joint = output.joints.first { $0.name == .leftWrist }
        XCTAssertEqual(joint?.normalizedPosition.x ?? -1, 0.3, accuracy: 1e-9)
        XCTAssertEqual(joint?.normalizedPosition.y ?? -1, 0.7, accuracy: 1e-9)
    }

    func testConfidenceIsPreserved() {
        var smoother = PoseSmoother()
        let input = pose([(.nose, CGPoint(x: 0.5, y: 0.5))], confidence: 0.42)
        let output = smoother.smooth(input, timestamp: 0)
        XCTAssertEqual(output.joints.first?.confidence ?? -1, 0.42, accuracy: 1e-6)
    }

    func testJointsSmoothedIndependently() {
        var smoother = PoseSmoother(minCutoff: 1.0, beta: 0.0)
        _ = smoother.smooth(
            pose([
                (.leftWrist, CGPoint(x: 0.0, y: 0.0)),
                (.rightWrist, CGPoint(x: 1.0, y: 1.0)),
            ]),
            timestamp: 0
        )
        // Move only the left wrist; the right should stay put (within the
        // filter's own steady-state, which for an unchanged input is exact).
        let out = smoother.smooth(
            pose([
                (.leftWrist, CGPoint(x: 0.5, y: 0.5)),
                (.rightWrist, CGPoint(x: 1.0, y: 1.0)),
            ]),
            timestamp: 0.06
        )
        let left = out.joints.first { $0.name == .leftWrist }!
        let right = out.joints.first { $0.name == .rightWrist }!
        // Left lags toward its new position (smoothed, so strictly between).
        XCTAssertGreaterThan(left.normalizedPosition.x, 0.0)
        XCTAssertLessThan(left.normalizedPosition.x, 0.5)
        // Right was constant → unchanged.
        XCTAssertEqual(right.normalizedPosition.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(right.normalizedPosition.y, 1.0, accuracy: 1e-9)
    }

    func testLargeTimeGapResetsAndPassesThrough() {
        var smoother = PoseSmoother(resetGap: 0.4)
        _ = smoother.smooth(pose([(.nose, CGPoint(x: 0.1, y: 0.1))]), timestamp: 0)
        // Jump well past resetGap — treated as a seek, so the new pose
        // passes through unsmoothed.
        let out = smoother.smooth(
            pose([(.nose, CGPoint(x: 0.9, y: 0.9))]),
            timestamp: 5.0
        )
        let nose = out.joints.first!
        XCTAssertEqual(nose.normalizedPosition.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(nose.normalizedPosition.y, 0.9, accuracy: 1e-9)
    }

    func testBackwardTimestampResets() {
        var smoother = PoseSmoother()
        _ = smoother.smooth(pose([(.nose, CGPoint(x: 0.1, y: 0.1))]), timestamp: 2.0)
        let out = smoother.smooth(
            pose([(.nose, CGPoint(x: 0.8, y: 0.8))]),
            timestamp: 1.0  // backward
        )
        XCTAssertEqual(out.joints.first?.normalizedPosition.x ?? -1, 0.8, accuracy: 1e-9)
    }

    func testNewlyAppearingJointPassesThroughOnFirstSight() {
        var smoother = PoseSmoother(minCutoff: 1.0, beta: 0.0)
        _ = smoother.smooth(pose([(.leftWrist, CGPoint(x: 0.2, y: 0.2))]), timestamp: 0)
        // rightWrist shows up for the first time on the second frame — it
        // has no history, so it should pass through exactly.
        let out = smoother.smooth(
            pose([
                (.leftWrist, CGPoint(x: 0.2, y: 0.2)),
                (.rightWrist, CGPoint(x: 0.8, y: 0.6)),
            ]),
            timestamp: 0.06
        )
        let right = out.joints.first { $0.name == .rightWrist }!
        XCTAssertEqual(right.normalizedPosition.x, 0.8, accuracy: 1e-9)
        XCTAssertEqual(right.normalizedPosition.y, 0.6, accuracy: 1e-9)
    }
}
