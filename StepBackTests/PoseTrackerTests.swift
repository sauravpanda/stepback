@testable import StepBack
import CoreGraphics
import Vision
import XCTest

final class PoseTrackerTests: XCTestCase {

    /// Builds a pose whose joints all sit at `center` (so its centroid is
    /// exactly `center`), with `count` joints at the given confidence.
    private func pose(
        at center: CGPoint,
        count: Int = 4,
        confidence: Float = 0.9
    ) -> DetectedPose {
        let names: [VNHumanBodyPoseObservation.JointName] =
            [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip,
             .leftWrist, .rightWrist, .leftAnkle]
        let joints = (0..<count).map { i in
            DetectedJoint(
                name: names[i % names.count],
                normalizedPosition: center,
                confidence: confidence
            )
        }
        return DetectedPose(joints: joints)
    }

    func testEmptyCandidatesReturnsNilAndKeepsLock() {
        var tracker = PoseTracker()
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.5, y: 0.5))])
        let before = tracker.lastCentroid
        XCTAssertNil(tracker.select(from: []))
        XCTAssertEqual(tracker.lastCentroid, before, "an empty frame must not lose the lock")
    }

    func testFirstSelectionPicksMostProminentAndIsNotContinuation() {
        var tracker = PoseTracker()
        let sparse = pose(at: CGPoint(x: 0.2, y: 0.5), count: 3)
        let rich = pose(at: CGPoint(x: 0.8, y: 0.5), count: 7)
        let sel = tracker.select(from: [sparse, rich])
        XCTAssertEqual(sel?.pose, rich, "first lock should pick the most-joints candidate")
        XCTAssertEqual(sel?.isContinuation, false)
    }

    func testFollowsNearestEvenWhenAnotherHasMoreJoints() {
        var tracker = PoseTracker(gate: 0.22)
        // Lock onto a person at x=0.3.
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.3, y: 0.5), count: 5)])
        // Next frame: the locked person drifted slightly to 0.33; a *richer*
        // person is far away at 0.85. We must keep following the near one.
        let near = pose(at: CGPoint(x: 0.33, y: 0.5), count: 4)
        let farRich = pose(at: CGPoint(x: 0.85, y: 0.5), count: 8)
        let sel = tracker.select(from: [farRich, near])
        XCTAssertEqual(sel?.pose, near, "should follow the nearest, not the most prominent")
        XCTAssertEqual(sel?.isContinuation, true)
    }

    func testReanchorsWhenNearestExceedsGate() {
        var tracker = PoseTracker(gate: 0.22)
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.2, y: 0.2), count: 5)])
        // The tracked person vanished; the only candidates are far away
        // (> gate). Re-anchor to the most prominent of them.
        let a = pose(at: CGPoint(x: 0.8, y: 0.8), count: 4)
        let b = pose(at: CGPoint(x: 0.9, y: 0.9), count: 7)
        let sel = tracker.select(from: [a, b])
        XCTAssertEqual(sel?.pose, b)
        XCTAssertEqual(sel?.isContinuation, false, "crossing the gate is a re-anchor")
    }

    func testResetReturnsToFirstLockBehaviour() {
        var tracker = PoseTracker()
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.3, y: 0.3), count: 5)])
        tracker.reset()
        XCTAssertNil(tracker.lastCentroid)
        // After reset, even a far candidate is accepted as a fresh lock.
        let sel = tracker.select(from: [pose(at: CGPoint(x: 0.9, y: 0.9), count: 4)])
        XCTAssertEqual(sel?.isContinuation, false)
    }

    func testTieOnJointCountBrokenByConfidence() {
        var tracker = PoseTracker()
        let lowConf = pose(at: CGPoint(x: 0.3, y: 0.5), count: 5, confidence: 0.4)
        let highConf = pose(at: CGPoint(x: 0.7, y: 0.5), count: 5, confidence: 0.95)
        let sel = tracker.select(from: [lowConf, highConf])
        XCTAssertEqual(sel?.pose, highConf)
    }

    // MARK: - Pinning

    func testPinFollowsNearestToPinnedPointEvenIfFarFromPriorLock() {
        var tracker = PoseTracker(gate: 0.22)
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.2, y: 0.5), count: 6)])
        // User long-presses a different dancer at x=0.8.
        tracker.pin(to: CGPoint(x: 0.8, y: 0.5))
        XCTAssertTrue(tracker.isPinned)
        let pinnedOne = pose(at: CGPoint(x: 0.82, y: 0.5), count: 3)
        let sel = tracker.select(from: [
            pose(at: CGPoint(x: 0.2, y: 0.5), count: 6),  // prominent, but not pinned
            pinnedOne,
        ])
        XCTAssertEqual(sel?.pose, pinnedOne)
    }

    func testPinnedModeHoldsRatherThanReanchoringWhenPersonGone() {
        var tracker = PoseTracker(gate: 0.22)
        tracker.pin(to: CGPoint(x: 0.3, y: 0.5))
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.3, y: 0.5), count: 4)])
        // Pinned person vanishes; only a far candidate remains. Auto mode
        // would grab it — pinned mode must hold (nil).
        let sel = tracker.select(from: [pose(at: CGPoint(x: 0.9, y: 0.9), count: 8)])
        XCTAssertNil(sel, "pinned tracker should hold, not jump to another dancer")
    }

    func testPinnedPersonReacquiredWhenTheyReturn() {
        var tracker = PoseTracker(gate: 0.22)
        tracker.pin(to: CGPoint(x: 0.3, y: 0.5))
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.3, y: 0.5), count: 4)])
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.9, y: 0.9), count: 8)])  // gone → held
        // They return near where they were pinned.
        let returned = pose(at: CGPoint(x: 0.32, y: 0.5), count: 4)
        let sel = tracker.select(from: [returned])
        XCTAssertEqual(sel?.pose, returned)
    }

    func testUnpinReturnsToAutoReanchoring() {
        var tracker = PoseTracker(gate: 0.22)
        tracker.pin(to: CGPoint(x: 0.3, y: 0.5))
        _ = tracker.select(from: [pose(at: CGPoint(x: 0.3, y: 0.5), count: 4)])
        tracker.unpin()
        XCTAssertFalse(tracker.isPinned)
        // A far prominent candidate should now be picked up (auto re-anchor).
        let other = pose(at: CGPoint(x: 0.9, y: 0.9), count: 8)
        let sel = tracker.select(from: [other])
        XCTAssertEqual(sel?.pose, other)
        XCTAssertEqual(sel?.isContinuation, false)
    }

    func testResetClearsPin() {
        var tracker = PoseTracker()
        tracker.pin(to: CGPoint(x: 0.5, y: 0.5))
        tracker.reset()
        XCTAssertFalse(tracker.isPinned)
        XCTAssertNil(tracker.lastCentroid)
    }

    // MARK: - Centroid

    func testCentroidIsAverageOfJoints() {
        let p = DetectedPose(joints: [
            DetectedJoint(name: .leftHip, normalizedPosition: CGPoint(x: 0.2, y: 0.4), confidence: 1),
            DetectedJoint(name: .rightHip, normalizedPosition: CGPoint(x: 0.6, y: 0.8), confidence: 1),
        ])
        let c = PoseTracker.centroid(p)
        XCTAssertEqual(c.x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(c.y, 0.6, accuracy: 1e-9)
    }

    func testCentroidOfEmptyPoseIsZero() {
        XCTAssertEqual(PoseTracker.centroid(DetectedPose(joints: [])), .zero)
    }
}
