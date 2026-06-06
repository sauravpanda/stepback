import CoreGraphics
import Foundation

/// Geometric scoring for how well an individual body segment supports a
/// stacked, balanced posture. Pure logic, no view dependencies — tested
/// directly in `WeightStackingEvaluatorTests`.
///
/// We deliberately don't try to identify the "posted" (weight-bearing)
/// foot here. That requires temporal tracking — which foot has been
/// stationary, how long, which side the centre of mass is currently over —
/// and lands cleanly in a v2 that buffers frames. For v1 we colour each
/// bone against a *static* reference: legs and torso want to be vertical,
/// hip and shoulder lines want to be level. A dancer mid-step will see
/// bones flash red and that's correct — they're not stacked, they're in
/// motion. Holding a balanced position will paint everything green.
enum WeightStackingEvaluator {

    /// What axis a bone should align with when the body is stacked.
    enum PreferredAxis: Equatable {
        /// Legs, torso sides — vertical when stacked.
        case vertical
        /// Shoulder and hip lines — horizontal when stacked.
        case horizontal
        /// Arms and other freely-moving segments — always full credit.
        case neutral
    }

    /// 0.0 = wildly off-axis, 1.0 = perfectly aligned. Score curve is
    /// linear in angle: 0° → 1.0, 22.5° → 0.5, 45° → 0. A 45° miss is the
    /// floor — anything past that just stays red.
    ///
    /// Degenerate input (zero-length bone) returns 1.0 rather than NaN
    /// or 0; the most graceful thing for the overlay is to render it as
    /// "fine" and let the next frame's better data dominate.
    static func alignmentScore(
        from start: CGPoint,
        to end: CGPoint,
        axis: PreferredAxis
    ) -> Double {
        if axis == .neutral { return 1.0 }
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return 1.0 }

        let alongAxis: Double
        switch axis {
        case .vertical:
            alongAxis = abs(dy) / length
        case .horizontal:
            alongAxis = abs(dx) / length
        case .neutral:
            return 1.0
        }
        // Clamp to [0, 1] before acos — floating-point drift can produce
        // 1.0000000001 which would crash acos with NaN.
        let clamped = min(1.0, max(0.0, alongAxis))
        let angleFromAxis = acos(clamped)
        let threshold: Double = .pi / 4   // 45° = full red
        return max(0, 1.0 - angleFromAxis / threshold)
    }

    // MARK: - Center of mass

    /// Estimates a 2-D centre of mass from the torso joints. The pelvis
    /// carries the bulk of body mass, so the hip midpoint is weighted more
    /// than the shoulder midpoint; the blend lands roughly at the navel,
    /// which is a serviceable single-camera CoM proxy.
    ///
    /// Requires *both* joints of a pair to use that pair — a lone hip joint
    /// is not the pelvis centre, and trusting it would skew the CoM toward
    /// whichever side Vision happened to see. Returns nil when neither pair
    /// is fully available.
    static func centerOfMass(
        leftHip: CGPoint?, rightHip: CGPoint?,
        leftShoulder: CGPoint?, rightShoulder: CGPoint?,
        hipWeight: Double = 0.65
    ) -> CGPoint? {
        let hipMid = midpoint(leftHip, rightHip)
        let shoulderMid = midpoint(leftShoulder, rightShoulder)

        switch (hipMid, shoulderMid) {
        case let (hip?, shoulder?):
            let w = max(0, min(1, hipWeight))
            return CGPoint(
                x: hip.x * w + shoulder.x * (1 - w),
                y: hip.y * w + shoulder.y * (1 - w)
            )
        case let (hip?, nil):
            return hip
        case let (nil, shoulder?):
            return shoulder
        case (nil, nil):
            return nil
        }
    }

    /// How well the centre of mass is stacked over a foot, measured
    /// horizontally. 1.0 = directly over an ankle (stacked), 0.5 = midway
    /// between the feet (weight split / uncommitted), 0.0 = a full
    /// stance-width or more outside the nearer foot (off balance).
    ///
    /// Normalising by stance width makes the score scale-free: a wide base
    /// and a narrow base both read "stacked" when the CoM is over a foot.
    /// `minStance` floors the denominator so feet-together stances don't
    /// divide by ~zero.
    static func comStackingScore(
        comX: CGFloat,
        leftAnkleX: CGFloat,
        rightAnkleX: CGFloat,
        minStance: CGFloat = 1
    ) -> Double {
        let stance = abs(leftAnkleX - rightAnkleX)
        let reference = max(stance, minStance)
        let nearest = min(abs(comX - leftAnkleX), abs(comX - rightAnkleX))
        return max(0, 1 - Double(nearest / reference))
    }

    private static func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        guard let a, let b else { return nil }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}
