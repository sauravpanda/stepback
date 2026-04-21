import AVFoundation
import CoreMedia
import Foundation
import Photos
import UIKit

enum PhotosError: Error, Equatable {
    case authorizationDenied
    case assetNotFound(identifier: String)
    case notAVURLAsset
    case thumbnailGenerationFailed
    case jpegEncodingFailed
}

protocol PhotosServicing: AnyObject, Sendable {
    func requestAuthorization() async -> PHAuthorizationStatus
    func currentAuthorizationStatus() -> PHAuthorizationStatus
    func resolveAVAsset(for identifier: String) async throws -> AVURLAsset
    func generateThumbnail(for asset: AVAsset, targetSize: CGSize) async throws -> Data
}

extension PhotosServicing {
    func generateThumbnail(for asset: AVAsset) async throws -> Data {
        try await generateThumbnail(for: asset, targetSize: CGSize(width: 400, height: 400))
    }
}

final class PhotosService: PhotosServicing, @unchecked Sendable {

    private let imageManager: PHImageManager
    private let thumbnailCompressionQuality: CGFloat

    init(
        imageManager: PHImageManager = .default(),
        thumbnailCompressionQuality: CGFloat = 0.7
    ) {
        self.imageManager = imageManager
        self.thumbnailCompressionQuality = thumbnailCompressionQuality
    }

    // MARK: - Authorization

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Asset resolution

    func resolveAVAsset(for identifier: String) async throws -> AVURLAsset {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw PhotosError.assetNotFound(identifier: identifier)
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: PhotosError.notAVURLAsset)
                    return
                }
                continuation.resume(returning: urlAsset)
            }
        }
    }

    // MARK: - Thumbnails

    func generateThumbnail(for asset: AVAsset, targetSize: CGSize) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let duration = try await asset.load(.duration).seconds
        let grabSeconds = duration > 1 ? 0.5 : max(0, duration / 2)
        let time = CMTime(seconds: grabSeconds, preferredTimescale: 600)

        let cgImage: CGImage
        do {
            (cgImage, _) = try await generator.image(at: time)
        } catch {
            throw PhotosError.thumbnailGenerationFailed
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpeg = uiImage.jpegData(compressionQuality: thumbnailCompressionQuality) else {
            throw PhotosError.jpegEncodingFailed
        }
        return jpeg
    }
}
