import CoreGraphics
import Foundation
import ImageIO

extension CGImagePropertyOrientation {

    /// Decodes the rotation embedded in an `AVAssetTrack.preferredTransform`
    /// into a `CGImagePropertyOrientation` we can hand to Vision.
    ///
    /// iPhone-shot portrait videos are stored landscape with a 90° CW
    /// transform — without this decode we'd tell Vision the image is
    /// `.up`, and Vision would try to detect a sideways body and quietly
    /// miss. Falls back to `.up` for anything we don't recognise (skewed
    /// transforms, near-identity edge cases) so behaviour matches the
    /// pre-orientation code on weird sources.
    ///
    /// We deliberately don't handle the mirror variants for now —
    /// `AVPlayerItemVideoOutput` doesn't pre-mirror selfie-camera buffers
    /// for us, but the visual flip is small enough that Vision still
    /// detects fine. Revisit if a real front-camera clip drifts.
    init(transform: CGAffineTransform) {
        let angle = atan2(transform.b, transform.a)
        let tolerance = 0.1
        if abs(angle) < tolerance {
            self = .up
        } else if abs(angle - .pi / 2) < tolerance {
            self = .right
        } else if abs(angle - .pi) < tolerance || abs(angle + .pi) < tolerance {
            self = .down
        } else if abs(angle + .pi / 2) < tolerance {
            self = .left
        } else {
            self = .up
        }
    }

    /// True when this orientation rotates the source by 90° — i.e. the
    /// upright image's width and height are swapped from the storage
    /// buffer's. Drives the `imageSize` axis swap in the coordinator so the
    /// overlay maps joint coords to the *displayed* aspect, not storage.
    var swapsAxes: Bool {
        switch self {
        case .left, .right, .leftMirrored, .rightMirrored: true
        default: false
        }
    }
}
