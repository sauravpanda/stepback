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

    func testResolveAVAssetThrowsAssetNotFoundForBogusIdentifier() async {
        let service = PhotosService()
        do {
            _ = try await service.resolveAVAsset(for: "definitely-not-a-real-asset-id")
            XCTFail("Expected PhotosError.assetNotFound")
        } catch let error as PhotosError {
            XCTAssertEqual(error, PhotosError.assetNotFound(identifier: "definitely-not-a-real-asset-id"))
        } catch {
            XCTFail("Expected PhotosError, got \(error)")
        }
    }

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
