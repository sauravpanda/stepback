@testable import StepBack
import AVFoundation
import XCTest

final class OriginalImportServiceTests: XCTestCase {

    private var temporarySource: URL!
    private var copiedFileNames: [String] = []

    override func setUpWithError() throws {
        // A tiny non-empty file we can copy without bringing in real video assets.
        let tmpName = "stepback-test-\(UUID().uuidString).mov"
        temporarySource = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(tmpName)
        try Data("not really a video".utf8)
            .write(to: temporarySource)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporarySource)
        for name in copiedFileNames {
            OriginalStorage.deleteIfExists(name: name)
        }
        copiedFileNames.removeAll()
    }

    // MARK: - OriginalStorage

    func testOriginalStorageDirectoryIsUnderDocumentsAndIsAlwaysCreatable() throws {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        XCTAssertTrue(
            OriginalStorage.directory.path.hasPrefix(docs.path),
            "Originals must live under Documents/, not tmp/ or caches/"
        )

        try OriginalStorage.ensureDirectoryExists()
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: OriginalStorage.directory.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testOriginalStorageFileURLAppendsName() {
        let url = OriginalStorage.fileURL(name: "abc.mov")
        XCTAssertEqual(url.lastPathComponent, "abc.mov")
        XCTAssertEqual(
            url.deletingLastPathComponent().path,
            OriginalStorage.directory.path
        )
    }

    func testDeleteIfExistsIsIdempotentOnMissingFile() {
        // No throw, no crash for a name that was never written.
        OriginalStorage.deleteIfExists(name: "never-written-\(UUID().uuidString).mov")
    }

    // MARK: - OriginalImportService

    func testImportCopyWritesFileAndReturnsName() async throws {
        let asset = AVURLAsset(url: temporarySource)
        let service = OriginalImportService()

        let fileName = try await service.importCopy(of: asset)
        copiedFileNames.append(fileName)

        let destination = OriginalStorage.fileURL(name: fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(
            try Data(contentsOf: destination),
            try Data(contentsOf: temporarySource),
            "The sandboxed copy should byte-match the source."
        )
    }

    func testImportCopyPreservesExtension() async throws {
        let asset = AVURLAsset(url: temporarySource)
        let fileName = try await OriginalImportService().importCopy(of: asset)
        copiedFileNames.append(fileName)

        XCTAssertEqual(
            (fileName as NSString).pathExtension.lowercased(),
            "mov"
        )
    }

    func testImportCopyDefaultsToMovWhenSourceHasNoExtension() async throws {
        // Construct a copy of the source without an extension so the service
        // has to fall back to its default.
        let extlessURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("stepback-extless-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: temporarySource, to: extlessURL)
        defer { try? FileManager.default.removeItem(at: extlessURL) }

        let asset = AVURLAsset(url: extlessURL)
        let fileName = try await OriginalImportService().importCopy(of: asset)
        copiedFileNames.append(fileName)

        XCTAssertEqual(
            (fileName as NSString).pathExtension.lowercased(),
            "mov"
        )
    }

    func testImportCopyFailsWhenSourceMissing() async {
        let missingURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("stepback-missing-\(UUID().uuidString).mov")
        let asset = AVURLAsset(url: missingURL)

        do {
            _ = try await OriginalImportService().importCopy(of: asset)
            XCTFail("Expected copyFailed for a non-existent source.")
        } catch let error as OriginalImportError {
            switch error {
            case .copyFailed: break
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
