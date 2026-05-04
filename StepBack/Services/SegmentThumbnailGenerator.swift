import AVFoundation
import CoreGraphics
import Foundation
import UIKit

/// Generates a single-frame JPEG thumbnail for a `ClipSegment` from its parent
/// asset. Pulled from `startSeconds + 0.1` to skip the cut-in frame which is
/// often a dark transition or the wrong gesture.
enum SegmentThumbnailGenerator {

    static func generate(
        from asset: AVAsset,
        atSeconds seconds: Double,
        size: CGSize = CGSize(width: 200, height: 200),
        quality: CGFloat = 0.6
    ) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let target = CMTime(seconds: max(0, seconds + 0.1), preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: target)
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
        } catch {
            return nil
        }
    }
}
