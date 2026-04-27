import AVFoundation
import Foundation

enum TrimError: Error, LocalizedError {
    case invalidRange
    case exportFailed(String)
    case unknownExportState

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "The selected range is empty."
        case .exportFailed(let detail):
            return "Trim failed: \(detail)"
        case .unknownExportState:
            return "Trim ended in an unknown state."
        }
    }
}

/// Where trimmed clip files live inside the app sandbox. We keep these
/// out of `tmp` so they survive backgrounding and reboot, and out of
/// `caches` because we can't afford the OS reclaiming them mid-practice.
enum TrimStorage {
    static var directory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trims", isDirectory: true)
    }

    static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    static func fileURL(name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func deleteIfExists(name: String) {
        let url = fileURL(name: name)
        try? FileManager.default.removeItem(at: url)
    }
}

/// Exports a sub-range of an `AVAsset` to the sandbox using the passthrough
/// preset (no re-encode → fast, no quality loss). The caller owns the
/// returned filename; `TrimStorage.directory` resolves it back to a URL.
struct TrimExportService {

    func export(
        asset: AVAsset,
        start: Double,
        end: Double
    ) async throws -> (fileName: String, durationSeconds: Double) {
        let trimmed = max(0, end - start)
        guard trimmed > 0.05 else { throw TrimError.invalidRange }

        try TrimStorage.ensureDirectoryExists()

        let fileName = "\(UUID().uuidString).mov"
        let outputURL = TrimStorage.fileURL(name: fileName)
        // Stale temp from a prior crashed export.
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw TrimError.exportFailed("Couldn't create export session.")
        }

        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false
        let timescale: CMTimeScale = 600
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            end: CMTime(seconds: end, preferredTimescale: timescale)
        )

        await session.export()

        switch session.status {
        case .completed:
            return (fileName, trimmed)
        case .failed, .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            let detail = session.error?.localizedDescription ?? "unknown"
            throw TrimError.exportFailed(detail)
        default:
            try? FileManager.default.removeItem(at: outputURL)
            throw TrimError.unknownExportState
        }
    }
}
