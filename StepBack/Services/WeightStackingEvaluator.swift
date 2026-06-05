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
}
