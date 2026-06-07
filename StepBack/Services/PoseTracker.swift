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
    /// centroid and the previous one for them to count as the same person.
    let gate: Double

    private(set) var lastCentroid: CGPoint?
    /// When the user has explicitly chosen a dancer, we follow *only* them:
    /// if the pinned person isn't near `lastCentroid` this frame we hold
    /// (return nil) and wait rather than auto-grabbing someone else. This is
    /// what stops the skeleton "randomly changing" on a crowded floor.
    private(set) var isPinned: Bool = false

    init(gate: Double = 0.22) {
        self.gate = gate
    }

    /// Returns the pose to display this frame, or nil if there's no person to
    /// show. In auto mode an empty frame leaves `lastCentroid` untouched so a
    /// brief dropout doesn't lose the lock; in pinned mode we also return nil
    /// (and hold) when the pinned dancer isn't within `gate`.
    mutating func select(from candidates: [DetectedPose]) -> Selection? {
        guard !candidates.isEmpty else { return nil }

        if let last = lastCentroid {
            let nearest = candidates.min(by: {
                Self.distance(Self.centroid($0), last)
                    < Self.distance(Self.centroid($1), last)
            })!
            let near = Self.distance(Self.centroid(nearest), last) <= gate

            if near {
                lastCentroid = Self.centroid(nearest)
                return Selection(pose: nearest, isContinuation: true)
            }
            if isPinned {
                // Pinned dancer not in range — hold and keep waiting for them.
                // Don't move lastCentroid; they may return near the same spot,
                // or the user can re-pin someone else.
                return nil
            }
            // Auto mode: the tracked person left — re-anchor to the most
            // prominent candidate.
            let prominent = mostProminent(candidates)
            lastCentroid = Self.centroid(prominent)
            return Selection(pose: prominent, isContinuation: false)
        }

        // No lock yet (auto, first frame): take the most prominent person.
        let prominent = mostProminent(candidates)
        lastCentroid = Self.centroid(prominent)
        return Selection(pose: prominent, isContinuation: false)
    }

    /// Locks tracking to whoever is nearest `centroid` (a normalized image
    /// point, e.g. mapped from a long-press). Subsequent frames follow only
    /// that person until unpinned or reset.
    mutating func pin(to centroid: CGPoint) {
        lastCentroid = centroid
        isPinned = true
    }

    /// Returns to automatic tracking, keeping the current lock as the
    /// starting point so the skeleton doesn't jump on release.
    mutating func unpin() {
        isPinned = false
    }

    mutating func reset() {
        lastCentroid = nil
        isPinned = false
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
