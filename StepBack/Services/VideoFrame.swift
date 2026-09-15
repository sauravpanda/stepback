import CoreGraphics
import Foundation

/// Where the picture actually is inside the player area.
///
/// `AVPlayerLayer` letterboxes with `.resizeAspect`, so a landscape clip on
/// a portrait phone sits in a band across the middle with black above and
/// below. Anything meant to be *on the video* — the beat overlay — has to
/// know that band, or it lands in the black.
enum VideoFrame {

    /// The aspect-fit rectangle of a video of `videoSize` inside `container`,
    /// after `quarterTurns` of rotation (odd turns swap width and height).
    /// Falls back to the whole container when the size isn't known.
    static func aspectFitRect(videoSize: CGSize, in container: CGSize, quarterTurns: Int = 0) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let swap = ((quarterTurns % 2) + 2) % 2 == 1
        let width = swap ? videoSize.height : videoSize.width
        let height = swap ? videoSize.width : videoSize.height
        let scale = min(container.width / width, container.height / height)
        let fitted = CGSize(width: width * scale, height: height * scale)
        return CGRect(
            x: (container.width - fitted.width) / 2,
            y: (container.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// A track's natural size with its preferred transform applied, so a
    /// phone video shot upright reports as portrait rather than as the
    /// landscape buffer it is stored in.
    static func orientedSize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let transformed = naturalSize.applying(preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}
