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
