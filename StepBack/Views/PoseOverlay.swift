import SwiftUI
import Vision

/// Renders a Vision body-pose skeleton over a video frame. Sized to its
/// parent via `GeometryReader`; the parent is expected to be the same
/// surface that displays the video at aspect-fit, so the joint coordinates
/// land on the actual body, not on the letterboxed black area.
struct PoseOverlay: View {

    let pose: DetectedPose?
    let imageSize: CGSize?

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
            }
        }
        .allowsHitTesting(false)
    }

    private func drawBones(
        pose: DetectedPose,
        displayRect: CGRect,
        context: GraphicsContext
    ) {
        let lookup = Dictionary(
            uniqueKeysWithValues: pose.joints.map { ($0.name, $0) }
        )
        for (start, end) in Self.skeletonEdges {
            guard let a = lookup[start], let b = lookup[end] else { continue }
            let pa = PoseCoordinateTransform.viewPoint(
                normalizedImagePoint: a.normalizedPosition,
                displayRect: displayRect
            )
            let pb = PoseCoordinateTransform.viewPoint(
                normalizedImagePoint: b.normalizedPosition,
                displayRect: displayRect
            )
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            let alpha = min(CGFloat(a.confidence), CGFloat(b.confidence))
            context.stroke(
                path,
                with: .color(Theme.Color.accent.opacity(alpha)),
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
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Theme.Color.accent.opacity(alpha))
            )
        }
    }

    /// Bone connections we draw. Face is omitted by default — eyes/ears
    /// rarely have high enough confidence on dance footage and add noise.
    /// Add them back if 3D / face detection becomes interesting later.
    private static let skeletonEdges: [(
        VNHumanBodyPoseObservation.JointName,
        VNHumanBodyPoseObservation.JointName
    )] = [
        // torso
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        // arms
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        // legs
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
    ]
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
