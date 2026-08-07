import AVFoundation
import os
import Photos
@testable import StepBack
import XCTest

final class PhotosServiceTests: XCTestCase {

    func testPhotosErrorEquatable() {
        XCTAssertEqual(PhotosError.authorizationDenied, PhotosError.authorizationDenied)
        XCTAssertEqual(
            PhotosError.assetNotFound(identifier: "abc"),
            PhotosError.assetNotFound(identifier: "abc")
        )
        XCTAssertNotEqual(
            PhotosError.assetNotFound(identifier: "a"),
            PhotosError.assetNotFound(identifier: "b")
        )
        XCTAssertNotEqual(PhotosError.notAVURLAsset, PhotosError.thumbnailGenerationFailed)
    }

    // Note: a live `resolveAVAsset(for:)` test against PHAsset.fetchAssets is
    // flaky in the CI simulator (the framework blocks on the photo-library
    // consent prompt even for a bogus identifier lookup, and the test harness
    // times out). Exercise the happy and error paths through a real device run
    // or a PHImageManager mock once one is wired up in a future change.

    func testCurrentAuthorizationStatusReturnsAValidCase() {
        let service = PhotosService()
        let status = service.currentAuthorizationStatus()
        // Sanity: the returned status must be one of the known cases.
        let valid: Set<PHAuthorizationStatus> = [
            .notDetermined, .restricted, .denied, .authorized, .limited
        ]
        XCTAssertTrue(valid.contains(status))
    }

    // MARK: - Cloud-identifier healing

    /// PhotosServicing stub whose local-identifier resolution is scripted per
    /// identifier, so the healing extension can be exercised without Photos.
    private final class StubPhotosService: PhotosServicing, @unchecked Sendable {
        var assetsByLocalIdentifier: [String: AVURLAsset] = [:]
        var localIdentifierByCloudIdentifier: [String: String] = [:]
        var resolveError: Error?

        func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
        func currentAuthorizationStatus() -> PHAuthorizationStatus { .authorized }

        func resolveAVAsset(for identifier: String) async throws -> AVURLAsset {
            if let resolveError { throw resolveError }
            guard let asset = assetsByLocalIdentifier[identifier] else {
                throw PhotosError.assetNotFound(identifier: identifier)
            }
            return asset
        }

        func generateThumbnail(for asset: AVAsset, targetSize: CGSize) async throws -> Data {
            Data()
        }

        func cloudIdentifier(forLocalIdentifier identifier: String) -> String? {
            localIdentifierByCloudIdentifier.first { $0.value == identifier }?.key
        }

        func localIdentifier(forCloudIdentifier cloudIdentifier: String) -> String? {
            localIdentifierByCloudIdentifier[cloudIdentifier]
        }
    }

    func testHealingResolveReturnsDirectlyWhenLocalIdentifierIsValid() async throws {
        let stub = StubPhotosService()
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/a.mov"))
        stub.assetsByLocalIdentifier["LOCAL-1"] = asset

        let resolved = try await stub.resolveAVAsset(localIdentifier: "LOCAL-1", cloudIdentifier: "CLOUD-1")

        XCTAssertIdentical(resolved.asset, asset)
        XCTAssertNil(resolved.remappedLocalIdentifier, "no healing needed → no remap reported")
    }

    func testHealingResolveRemapsThroughCloudIdentifier() async throws {
        // The stored local identifier is stale; the cloud identifier still
        // maps to the asset under a fresh local identifier.
        let stub = StubPhotosService()
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/b.mov"))
        stub.assetsByLocalIdentifier["LOCAL-NEW"] = asset
        stub.localIdentifierByCloudIdentifier["CLOUD-1"] = "LOCAL-NEW"

        let resolved = try await stub.resolveAVAsset(localIdentifier: "LOCAL-STALE", cloudIdentifier: "CLOUD-1")

        XCTAssertIdentical(resolved.asset, asset)
        XCTAssertEqual(resolved.remappedLocalIdentifier, "LOCAL-NEW")
    }

    func testHealingResolveRethrowsWhenNoCloudIdentifier() async {
        let stub = StubPhotosService()

        do {
            _ = try await stub.resolveAVAsset(localIdentifier: "LOCAL-STALE", cloudIdentifier: nil)
            XCTFail("expected assetNotFound")
        } catch let error as PhotosError {
            XCTAssertEqual(error, .assetNotFound(identifier: "LOCAL-STALE"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHealingResolveRethrowsWhenCloudMappingPointsBackAtStaleIdentifier() async {
        // Guards the `healed != localIdentifier` check: a mapping that
        // returns the same dead identifier must not loop into a second fetch.
        let stub = StubPhotosService()
        stub.localIdentifierByCloudIdentifier["CLOUD-1"] = "LOCAL-STALE"

        do {
            _ = try await stub.resolveAVAsset(localIdentifier: "LOCAL-STALE", cloudIdentifier: "CLOUD-1")
            XCTFail("expected assetNotFound")
        } catch let error as PhotosError {
            XCTAssertEqual(error, .assetNotFound(identifier: "LOCAL-STALE"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - ResumeOnce (the #53 double-resume guard)

    func testResumeOnceRunsBodyExactlyOnce() {
        let guardOnce = ResumeOnce()
        var count = 0
        guardOnce.run { count += 1 }
        guardOnce.run { count += 1 }
        guardOnce.run { count += 1 }
        XCTAssertEqual(count, 1, "only the first call should run")
    }

    func testResumeOnceIsThreadSafeUnderConcurrency() {
        // Hammer it from many threads at once; exactly one body must run —
        // this is the property that prevents the continuation double-resume.
        let guardOnce = ResumeOnce()
        let counter = OSAllocatedUnfairLock(initialState: 0)
        let iterations = 1_000
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            guardOnce.run { counter.withLock { $0 += 1 } }
        }
        XCTAssertEqual(counter.withLock { $0 }, 1, "exactly one body across \(iterations) racing calls")
    }
}
