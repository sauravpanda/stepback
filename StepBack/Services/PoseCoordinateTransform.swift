import CoreGraphics

/// Pure geometry helpers shared by `PoseOverlay` and any future pose surface.
/// Kept independent of SwiftUI / AVFoundation so the math is unit-testable
/// without a player or a view.
enum PoseCoordinateTransform {

    /// The rect occupied by a source image inside a container when fit
    /// aspect-correct — i.e. exactly what `AVPlayerLayer` does with
    /// `.videoGravity = .resizeAspect`. Letterboxes top/bottom for sources
    /// wider than the container, left/right for taller sources.
    ///
    /// Returns `.zero` for any zero dimension; the overlay treats this as
    /// "no joints to draw" and renders nothing.
    static func displayRect(
        imageSize: CGSize,
        in containerSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            // Source is wider than the container: fit width, letterbox top/bottom.
            let height = containerSize.width / imageAspect
            let y = (containerSize.height - height) / 2
            return CGRect(x: 0, y: y, width: containerSize.width, height: height)
        } else {
            // Source is taller (or equal): fit height, letterbox left/right.
            let width = containerSize.height * imageAspect
            let x = (containerSize.width - width) / 2
            return CGRect(x: x, y: 0, width: width, height: containerSize.height)
        }
    }

    /// Maps a Vision-space point (normalized 0…1, origin bottom-left) into
    /// view space (top-left origin) using the display rect from
    /// `displayRect(imageSize:in:)`. The Y axis is flipped to match SwiftUI.
    static func viewPoint(
        normalizedImagePoint: CGPoint,
        displayRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: displayRect.minX + normalizedImagePoint.x * displayRect.width,
            y: displayRect.minY + (1 - normalizedImagePoint.y) * displayRect.height
        )
    }
}
