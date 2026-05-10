import AVFoundation
import Foundation

enum OriginalImportError: Error, LocalizedError {
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let detail): "Couldn't copy video into the app: \(detail)"
        }
    }
}

/// Where sandboxed originals live. Same rationale as `TrimStorage`:
/// `Documents/` (not `tmp` or `caches`) so the OS can't reclaim them
/// mid-practice, and we own them across PHAsset deletions.
enum OriginalStorage {
    static var directory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Originals", isDirectory: true)
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

/// Copies an `AVURLAsset` resolved from the user's Photos library into the
/// app sandbox so the clip survives the original being deleted from Photos.
/// Returns the on-disk filename inside `OriginalStorage.directory`.
struct OriginalImportService {

    func importCopy(of urlAsset: AVURLAsset) async throws -> String {
        try OriginalStorage.ensureDirectoryExists()

        let sourceExt = urlAsset.url.pathExtension
        let ext = sourceExt.isEmpty ? "mov" : sourceExt
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = OriginalStorage.fileURL(name: fileName)

        // Stale destination from a prior crashed copy — extremely unlikely
        // given the UUID, but cheap insurance.
        try? FileManager.default.removeItem(at: destination)

        do {
            try FileManager.default.copyItem(at: urlAsset.url, to: destination)
            return fileName
        } catch {
            throw OriginalImportError.copyFailed(error.localizedDescription)
        }
    }
}
