import CoreGraphics
import Foundation

/// Chooses a single person to follow from the multiple poses Vision returns
/// per frame, using temporal continuity so the skeleton stops jumping
/// between dancers. Pure logic, tested directly.
///
/// Each frame we pick the candidate whose centroid is nearest the one we
/// chose last. Only when the nearest candidate is further than `gate` —
/// meaning the tracked dancer probably left the frame — do we re-anchor to
/// the most prominent person. The first frame (and any re-anchor) reports
/// `isContinuation == false` so the caller can reset per-joint smoothing,
/// which would otherwise smear a path between two different bodies.
struct PoseTracker {

    struct Selection: Equatable {
        let pose: DetectedPose
        /// False on the first lock and on a re-anchor (we switched people);
        /// true when this frame continues following the same person.
        let isContinuation: Bool
    }

    /// Max distance (normalized image units) between this frame's chosen
    /// centroid and the *predicted* one for them to count as the same person.
    let gate: Double
    /// If the second-nearest candidate is within this of the nearest (both
    /// plausibly "you"), a pinned tracker holds instead of guessing — this
    /// is what stops it hopping to a partner passing close.
    let ambiguityMargin: Double
    /// How much of the last frame's motion to project forward when
    /// predicting where the tracked dancer is now. Matching against the
    /// prediction (not the stale last position) stops a stationary passer-by
    /// near the old spot from stealing a fast-moving lock.
    let velocityDamping: Double

    private(set) var lastCentroid: CGPoint?
    private(set) var lastVelocity: CGVector = .zero
    /// When the user has explicitly chosen a dancer, we follow *only* them:
    /// if the pinned person isn't near the prediction this frame we hold
    /// (return nil) and wait rather than auto-grabbing someone else. This is
    /// what stops the skeleton "randomly changing" on a crowded floor.
    private(set) var isPinned: Bool = false

    init(
        gate: Double = 0.22,
        ambiguityMargin: Double = 0.05,
        velocityDamping: Double = 0.6
    ) {
        self.gate = gate
        self.ambiguityMargin = ambiguityMargin
        self.velocityDamping = velocityDamping
    }

    /// Where we expect the tracked dancer to be this frame: last position
    /// plus a damped projection of the last motion.
    var predictedCentroid: CGPoint? {
        guard let last = lastCentroid else { return nil }
        return CGPoint(
            x: last.x + velocityDamping * lastVelocity.dx,
            y: last.y + velocityDamping * lastVelocity.dy
        )
    }

    /// Returns the pose to display this frame, or nil if there's no person to
    /// show. In auto mode an empty frame leaves the lock untouched so a brief
    /// dropout doesn't lose it; in pinned mode we also return nil (and hold)
    /// when the pinned dancer isn't confidently identifiable this frame.
    mutating func select(from candidates: [DetectedPose]) -> Selection? {
        guard !candidates.isEmpty else { return nil }

        guard let predicted = predictedCentroid else {
            // No lock yet (auto, first frame): take the most prominent person.
            return adopt(mostProminent(candidates), isContinuation: false)
        }

        let ranked = candidates
            .map { ($0, Self.distance(Self.centroid($0), predicted)) }
            .sorted { $0.1 < $1.1 }
        let (best, bestDist) = ranked[0]

        if bestDist > gate {
            if isPinned {
                // Pinned dancer not where we expect — hold and wait. Don't
                // move the lock; they may return near the same spot.
                return nil
            }
            // Auto mode: the tracked person left — re-anchor to the most
            // prominent candidate.
            return adopt(mostProminent(candidates), isContinuation: false)
        }

        // A rival is almost as close as the best match. When pinned, refuse
        // to guess — hold so we don't hop to whoever's passing. (Auto mode
        // doesn't hold; momentary wrong picks there self-correct next frame.)
        if isPinned, ranked.count >= 2, ranked[1].1 - bestDist < ambiguityMargin {
            return nil
        }

        return adopt(best, isContinuation: true)
    }

    /// Locks tracking to whoever is nearest `centroid` (a normalized image
    /// point, e.g. mapped from a long-press). Subsequent frames follow only
    /// that person until unpinned or reset.
    mutating func pin(to centroid: CGPoint) {
        lastCentroid = centroid
        lastVelocity = .zero
        isPinned = true
    }

    /// Returns to automatic tracking, keeping the current lock as the
    /// starting point so the skeleton doesn't jump on release.
    mutating func unpin() {
        isPinned = false
    }

    mutating func reset() {
        lastCentroid = nil
        lastVelocity = .zero
        isPinned = false
    }

    /// Commits to `pose`, updating the lock position and the velocity
    /// estimate (the step from the previous lock to this one).
    private mutating func adopt(_ pose: DetectedPose, isContinuation: Bool) -> Selection {
        let c = Self.centroid(pose)
        if isContinuation, let last = lastCentroid {
            lastVelocity = CGVector(dx: c.x - last.x, dy: c.y - last.y)
        } else {
            lastVelocity = .zero
        }
        lastCentroid = c
        return Selection(pose: pose, isContinuation: isContinuation)
    }

    /// Most clearly-visible candidate: most joints, ties broken by mean
    /// confidence. Used for the first lock and for re-anchoring.
    private func mostProminent(_ candidates: [DetectedPose]) -> DetectedPose {
        candidates.max { a, b in
            if a.joints.count != b.joints.count {
                return a.joints.count < b.joints.count
            }
            return Self.meanConfidence(a) < Self.meanConfidence(b)
        }!
    }

    /// Average of a pose's joint positions — a cheap, stable centroid.
    static func centroid(_ pose: DetectedPose) -> CGPoint {
        guard !pose.joints.isEmpty else { return .zero }
        let sum = pose.joints.reduce(CGPoint.zero) { acc, joint in
            CGPoint(
                x: acc.x + joint.normalizedPosition.x,
                y: acc.y + joint.normalizedPosition.y
            )
        }
        let n = CGFloat(pose.joints.count)
        return CGPoint(x: sum.x / n, y: sum.y / n)
    }

    private static func meanConfidence(_ pose: DetectedPose) -> Float {
        guard !pose.joints.isEmpty else { return 0 }
        return pose.joints.reduce(0) { $0 + $1.confidence } / Float(pose.joints.count)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
