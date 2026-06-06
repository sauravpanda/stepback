import CoreGraphics
import Foundation
import Vision

/// Applies per-joint One-Euro smoothing to a stream of detected poses so the
/// rendered skeleton stops shimmering between frames. Each joint gets an
/// independent pair of x/y filters keyed by joint name; a joint that vanishes
/// and reappears simply picks up a fresh filter on its return.
///
/// Filter parameters are tuned for Vision's **normalized** coordinates
/// (0…1), where joint velocities are small (a hand crossing the frame in
/// half a second is ~2 units/s). `beta` is higher than a pixel-space default
/// would be so fast limbs don't lag.
struct PoseSmoother {

    let minCutoff: Double
    let beta: Double
    /// A timestep larger than this (seconds) is treated as a seek / scene
    /// cut: all filters reset so the skeleton snaps to the new frame instead
    /// of smearing a path between two unrelated poses.
    let resetGap: Double

    private struct JointFilter {
        var x: OneEuroFilter
        var y: OneEuroFilter
    }

    private var filters: [VNHumanBodyPoseObservation.JointName: JointFilter] = [:]
    private var lastTimestamp: Double?

    init(minCutoff: Double = 1.0, beta: Double = 0.5, resetGap: Double = 0.4) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.resetGap = resetGap
    }

    /// Returns a copy of `pose` with every joint position smoothed against
    /// the running history. `timestamp` should be a monotonic media clock;
    /// non-monotonic or large jumps reset the filters first.
    mutating func smooth(_ pose: DetectedPose, timestamp: Double) -> DetectedPose {
        if let last = lastTimestamp,
           timestamp <= last || timestamp - last > resetGap {
            filters.removeAll()
        }
        lastTimestamp = timestamp

        let smoothedJoints = pose.joints.map { joint -> DetectedJoint in
            var jointFilter = filters[joint.name] ?? JointFilter(
                x: OneEuroFilter(minCutoff: minCutoff, beta: beta),
                y: OneEuroFilter(minCutoff: minCutoff, beta: beta)
            )
            let sx = jointFilter.x.filter(
                Double(joint.normalizedPosition.x), timestamp: timestamp
            )
            let sy = jointFilter.y.filter(
                Double(joint.normalizedPosition.y), timestamp: timestamp
            )
            filters[joint.name] = jointFilter
            return DetectedJoint(
                name: joint.name,
                normalizedPosition: CGPoint(x: sx, y: sy),
                confidence: joint.confidence
            )
        }
        return DetectedPose(joints: smoothedJoints)
    }

    /// Forgets all joint history. Call when the underlying clip changes or
    /// detection is restarted.
    mutating func reset() {
        filters.removeAll()
        lastTimestamp = nil
    }
}
