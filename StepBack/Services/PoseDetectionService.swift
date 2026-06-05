import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// A single body joint detected by Vision in a frame.
struct DetectedJoint: Equatable, Sendable {
    let name: VNHumanBodyPoseObservation.JointName
    /// Vision coordinates: normalized 0…1, origin bottom-left of the image.
    let normalizedPosition: CGPoint
    let confidence: Float
}

/// One person's pose as a collection of joints above the confidence floor.
/// We intentionally don't model multiple people in v1 — the practice surface
/// is dancer-focused and grabbing the most-confident observation is enough
/// to verify the pipeline is working.
struct DetectedPose: Equatable, Sendable {
    let joints: [DetectedJoint]
}

enum PoseDetectionError: Error, LocalizedError {
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .visionFailed(let detail): "Pose detection failed: \(detail)"
        }
    }
}

/// Synchronous, Sendable Vision wrapper. Callers run it on a background
/// queue — `VNImageRequestHandler.perform(_:)` is blocking and can take
/// 10–30ms per frame on recent iPhones, more on older hardware.
struct PoseDetectionService: Sendable {

    /// Joints below this confidence are dropped. Apple's documented
    /// "reasonably reliable" floor is 0.3; we use 0.25 so dance footage
    /// — where wrists and ankles routinely sit just under 0.3 during
    /// transitions — keeps producing usable skeletons instead of flickering.
    /// Below 0.2 hands start drifting visibly; that's the real floor.
    let confidenceThreshold: Float

    init(confidenceThreshold: Float = 0.25) {
        self.confidenceThreshold = confidenceThreshold
    }

    func detect(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> DetectedPose? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            throw PoseDetectionError.visionFailed(error.localizedDescription)
        }
        guard let observation = (request.results ?? []).first else { return nil }
        let allPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
        do {
            allPoints = try observation.recognizedPoints(.all)
        } catch {
            throw PoseDetectionError.visionFailed(error.localizedDescription)
        }
        let joints = allPoints.compactMap { (name, point) -> DetectedJoint? in
            guard point.confidence >= confidenceThreshold else { return nil }
            return DetectedJoint(
                name: name,
                normalizedPosition: point.location,
                confidence: point.confidence
            )
        }
        return joints.isEmpty ? nil : DetectedPose(joints: joints)
    }
}
