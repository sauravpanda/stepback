import SwiftUI
import Vision

/// A bone in the rendered skeleton, plus what its "stacked" reference
/// axis is. Legs and torso sides want to be vertical; the hip and shoulder
/// lines want to be level. Arms are neutral — they fly around in dance and
/// scoring them against an axis would just paint them red constantly.
private struct SkeletonBone {
    let start: VNHumanBodyPoseObservation.JointName
    let end: VNHumanBodyPoseObservation.JointName
    let axis: WeightStackingEvaluator.PreferredAxis
}

/// Renders a Vision body-pose skeleton over a video frame. Sized to its
/// parent via `GeometryReader`; the parent is expected to be the same
/// surface that displays the video at aspect-fit, so the joint coordinates
/// land on the actual body, not on the letterboxed black area.
///
/// Bone colour reflects weight-stacking alignment: green when the segment
/// is close to its preferred reference axis, fading through yellow to red
/// as the dancer leaves a balanced position. Arms are left accent-coloured
/// because their orientation isn't a stacking signal.
///
/// `poseAge` drives an overall opacity so the user can see when the
/// skeleton being shown is the *current* detection vs one we're holding
/// from a few frames ago (Vision dropped them) — solid = fresh, faded =
/// almost stale.
struct PoseOverlay: View {

    let pose: DetectedPose?
    let imageSize: CGSize?
    /// Seconds since the last successful detection. The coordinator caps
    /// this at `staleAfter` (0.5s) before clearing `pose`.
    var poseAge: TimeInterval = 0

    /// Fade ramp parameters. Below `fadeStart` the skeleton is fully solid
    /// — every fresh detection looks the same. Past it we ramp linearly to
    /// 0 alpha at `fadeEnd`, which should match the coordinator's stale
    /// cutoff so a soon-to-be-cleared skeleton visibly fades before vanishing.
    private static let fadeStart: TimeInterval = 0.2
    private static let fadeEnd: TimeInterval = 0.5

    var body: some View {
        GeometryReader { geo in
            if let pose, let imageSize {
                let rect = PoseCoordinateTransform.displayRect(
                    imageSize: imageSize,
                    in: geo.size
                )
                Canvas { context, _ in
                    drawBones(pose: pose, displayRect: rect, context: context)
                    drawJoints(pose: pose, displayRect: rect, context: context)
                }
                .opacity(freshnessOpacity)
            }
        }
        .allowsHitTesting(false)
    }

    private var freshnessOpacity: Double {
        if poseAge <= Self.fadeStart { return 1.0 }
        if poseAge >= Self.fadeEnd { return 0.0 }
        return 1.0 - (poseAge - Self.fadeStart) / (Self.fadeEnd - Self.fadeStart)
    }

    private func drawBones(
        pose: DetectedPose,
        displayRect: CGRect,
        context: GraphicsContext
    ) {
        let lookup = Dictionary(
            uniqueKeysWithValues: pose.joints.map { ($0.name, $0) }
        )
        for bone in Self.skeleton {
            guard let a = lookup[bone.start], let b = lookup[bone.end] else { continue }
            let pa = PoseCoordinateTransform.viewPoint(
                normalizedImagePoint: a.normalizedPosition,
                displayRect: displayRect
            )
            let pb = PoseCoordinateTransform.viewPoint(
                normalizedImagePoint: b.normalizedPosition,
                displayRect: displayRect
            )
            // Stacking score → bone colour. Arms (axis: .neutral) come back
            // 1.0 → green; that reads as "no problem here," which matches
            // the intent (we're not making a claim about arms).
            let score = WeightStackingEvaluator.alignmentScore(
                from: pa, to: pb, axis: bone.axis
            )
            let tint = Color.stackingColor(for: score)
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            // Stroke alpha still tracks joint confidence so a wobbly
            // detection visibly weakens — but the hue carries the stacking
            // story regardless.
            let confidenceAlpha = min(CGFloat(a.confidence), CGFloat(b.confidence))
            context.stroke(
                path,
                with: .color(tint.opacity(confidenceAlpha)),
                lineWidth: 3
            )
        }
    }

    private func drawJoints(
        pose: DetectedPose,
        displayRect: CGRect,
        context: GraphicsContext
    ) {
        for joint in pose.joints {
            let p = PoseCoordinateTransform.viewPoint(
                normalizedImagePoint: joint.normalizedPosition,
                displayRect: displayRect
            )
            let radius: CGFloat = 4
            let rect = CGRect(
                x: p.x - radius,
                y: p.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let alpha = CGFloat(joint.confidence)
            // Joints stay white-ish so they read as anatomical landmarks
            // regardless of the surrounding bone colour. Confidence still
            // drives alpha — low-confidence joints dim out.
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color.white.opacity(alpha * 0.85))
            )
        }
    }

    /// Bone connections we draw, with their preferred reference axis for
    /// weight-stacking scoring. Face is omitted — eyes/ears rarely have
    /// high enough confidence on dance footage and the noise would dominate
    /// the colouring.
    private static let skeleton: [SkeletonBone] = [
        // shoulders & hips — level when stacked
        SkeletonBone(start: .leftShoulder, end: .rightShoulder, axis: .horizontal),
        SkeletonBone(start: .leftHip, end: .rightHip, axis: .horizontal),
        // torso sides — vertical when stacked
        SkeletonBone(start: .leftShoulder, end: .leftHip, axis: .vertical),
        SkeletonBone(start: .rightShoulder, end: .rightHip, axis: .vertical),
        // arms — neutral
        SkeletonBone(start: .leftShoulder, end: .leftElbow, axis: .neutral),
        SkeletonBone(start: .leftElbow, end: .leftWrist, axis: .neutral),
        SkeletonBone(start: .rightShoulder, end: .rightElbow, axis: .neutral),
        SkeletonBone(start: .rightElbow, end: .rightWrist, axis: .neutral),
        // legs — vertical when stacked
        SkeletonBone(start: .leftHip, end: .leftKnee, axis: .vertical),
        SkeletonBone(start: .leftKnee, end: .leftAnkle, axis: .vertical),
        SkeletonBone(start: .rightHip, end: .rightKnee, axis: .vertical),
        SkeletonBone(start: .rightKnee, end: .rightAnkle, axis: .vertical),
    ]
}

extension Color {
    /// Maps a `WeightStackingEvaluator` score to a stacking-themed colour:
    /// red at 0, yellow at 0.5, green at 1. Endpoint values are tuned to
    /// read well on top of black-letterboxed video — pure RGB primaries
    /// look harsh, so we soften red and green slightly.
    static func stackingColor(for score: Double) -> Color {
        let s = max(0, min(1, score))
        if s >= 0.5 {
            // Yellow → green
            let t = (s - 0.5) * 2
            return Color(
                red: 1.0 - 0.8 * t,
                green: 0.85,
                blue: 0.2 * t
            )
        } else {
            // Red → yellow
            let t = s * 2
            return Color(
                red: 1.0,
                green: 0.2 + 0.65 * t,
                blue: 0.0
            )
        }
    }
}

/// Small chip rendered above the video when pose detection is enabled, so
/// the dashboard can read "is this working?" at a glance without watching
/// the overlay redraw.
struct PoseStatusChip: View {
    let status: PoseStreamCoordinator.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    private var indicatorColor: Color {
        switch status {
        case .idle: Theme.Color.textTertiary
        case .waiting: .yellow
        case .detected: .green
        case .noPerson: .orange
        case .error: .red
        }
    }

    private var label: String {
        switch status {
        case .idle: "Pose off"
        case .waiting: "Detecting…"
        case .detected(let count): "Pose · \(count) joints"
        case .noPerson: "No person"
        case .error(let message): "Pose: \(message)"
        }
    }
}
