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

    // MARK: - Embedded source range

    // Trim files carry the [start, end] window (in the *original* asset's
    // timeline) they were exported from, encoded in the filename, so a
    // re-trim can re-export from the original instead of trimming the trim.
    // Format: `trim-<uuid>__<startMs>__<endMs>.mov`. Legacy trims named
    // `<uuid>.mov` simply return nil bounds (→ narrow-only fallback).

    static func makeFileName(start: Double, end: Double) -> String {
        let startMs = Int((max(0, start) * 1000).rounded())
        let endMs = Int((max(0, end) * 1000).rounded())
        return "trim-\(UUID().uuidString)__\(startMs)__\(endMs).mov"
    }

    static func bounds(fromName name: String) -> (start: Double, end: Double)? {
        let base = (name as NSString).deletingPathExtension
        let parts = base.components(separatedBy: "__")
        guard parts.count == 3,
              let startMs = Int(parts[1]),
              let endMs = Int(parts[2]),
              endMs > startMs else { return nil }
        return (Double(startMs) / 1000, Double(endMs) / 1000)
    }
}

/// Exports a sub-range of an `AVAsset` to the sandbox using the passthrough
/// preset (no re-encode → fast, no quality loss). The caller owns the
/// returned filename; `TrimStorage.directory` resolves it back to a URL.
/// The filename embeds `[start, end]` (see `TrimStorage.makeFileName`), so
/// `start`/`end` here must be in the *original* asset's timeline.
struct TrimExportService {

    func export(
        asset: AVAsset,
        start: Double,
        end: Double,
        recordsOriginalBounds: Bool = true
    ) async throws -> (fileName: String, durationSeconds: Double) {
        let trimmed = max(0, end - start)
        guard trimmed > 0.05 else { throw TrimError.invalidRange }

        try TrimStorage.ensureDirectoryExists()

        // Only embed the range when start/end are in the *original* timeline.
        // When trimming an already-trimmed fallback source they aren't, so we
        // write a legacy-style name (no bounds) → next edit treats it legacy.
        let fileName = recordsOriginalBounds
            ? TrimStorage.makeFileName(start: start, end: end)
            : "\(UUID().uuidString).mov"
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
