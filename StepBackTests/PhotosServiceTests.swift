import AVFoundation
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
}
