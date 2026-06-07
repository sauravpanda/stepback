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

    // MARK: - Inverse (touch → image)

    /// Undoes a center-anchored `scaleEffect(scale)` + `offset` and returns
    /// the touch location as a fraction (0…1) of the *unzoomed* container.
    /// This is the inverse of how `ZoomablePlayerContainer` displays its
    /// content, so a finger tap lands back in the content's own coordinates.
    static func unzoomedFraction(
        location: CGPoint,
        containerSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        guard containerSize.width > 0, containerSize.height > 0, scale > 0 else {
            return .zero
        }
        let cx = containerSize.width / 2
        let cy = containerSize.height / 2
        // screen = (content - center) * scale + center + offset  →  invert:
        let contentX = (location.x - offset.width - cx) / scale + cx
        let contentY = (location.y - offset.height - cy) / scale + cy
        return CGPoint(x: contentX / containerSize.width, y: contentY / containerSize.height)
    }

    /// Inverse of `viewPoint`: maps a container fraction (0…1, top-left
    /// origin — already un-zoomed via `unzoomedFraction`) to a normalized
    /// Vision image point (0…1, bottom-left origin). `displayRect` must be
    /// computed in a unit (1×1) container so it lives in the same fractional
    /// space. Flips Y back, and un-mirrors X when the video is mirrored.
    /// Returns nil if the fraction falls outside the letterboxed video.
    static func normalizedImagePoint(
        containerFraction f: CGPoint,
        unitDisplayRect: CGRect,
        mirrored: Bool
    ) -> CGPoint? {
        guard unitDisplayRect.width > 0, unitDisplayRect.height > 0 else { return nil }
        let nx = (f.x - unitDisplayRect.minX) / unitDisplayRect.width
        let nyTop = (f.y - unitDisplayRect.minY) / unitDisplayRect.height
        guard (0...1).contains(nx), (0...1).contains(nyTop) else { return nil }
        let imageX = mirrored ? (1 - nx) : nx
        let imageY = 1 - nyTop  // flip to Vision's bottom-left origin
        return CGPoint(x: imageX, y: imageY)
    }
}
