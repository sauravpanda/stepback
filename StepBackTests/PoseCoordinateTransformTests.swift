@testable import StepBack
import CoreGraphics
import XCTest

final class PoseCoordinateTransformTests: XCTestCase {

    private let accuracy: CGFloat = 0.0001

    // MARK: - displayRect

    func testDisplayRectMatchesContainerWhenAspectsMatch() {
        // 16:9 image into 16:9 container → fills exactly, no letterbox.
        let result = PoseCoordinateTransform.displayRect(
            imageSize: CGSize(width: 1920, height: 1080),
            in: CGSize(width: 400, height: 225)
        )
        XCTAssertEqual(result.origin.x, 0, accuracy: accuracy)
        XCTAssertEqual(result.origin.y, 0, accuracy: accuracy)
        XCTAssertEqual(result.width, 400, accuracy: accuracy)
        XCTAssertEqual(result.height, 225, accuracy: accuracy)
    }

    func testDisplayRectLetterboxesTopAndBottomForWideImage() {
        // 16:9 image (1.777…) into 1:1 container → fit width, letterbox y.
        let result = PoseCoordinateTransform.displayRect(
            imageSize: CGSize(width: 1600, height: 900),
            in: CGSize(width: 400, height: 400)
        )
        XCTAssertEqual(result.origin.x, 0, accuracy: accuracy)
        XCTAssertEqual(result.width, 400, accuracy: accuracy)
        // height = 400 / (1600/900) = 400 / 1.777… = 225
        XCTAssertEqual(result.height, 225, accuracy: accuracy)
        // centered vertically: (400 - 225) / 2 = 87.5
        XCTAssertEqual(result.origin.y, 87.5, accuracy: accuracy)
    }

    func testDisplayRectLetterboxesLeftAndRightForTallImage() {
        // 9:16 image (0.5625) into 1:1 container → fit height, letterbox x.
        let result = PoseCoordinateTransform.displayRect(
            imageSize: CGSize(width: 1080, height: 1920),
            in: CGSize(width: 400, height: 400)
        )
        XCTAssertEqual(result.origin.y, 0, accuracy: accuracy)
        XCTAssertEqual(result.height, 400, accuracy: accuracy)
        // width = 400 * (1080/1920) = 400 * 0.5625 = 225
        XCTAssertEqual(result.width, 225, accuracy: accuracy)
        // centered horizontally: (400 - 225) / 2 = 87.5
        XCTAssertEqual(result.origin.x, 87.5, accuracy: accuracy)
    }

    func testDisplayRectIsZeroForZeroImage() {
        XCTAssertEqual(
            PoseCoordinateTransform.displayRect(
                imageSize: .zero,
                in: CGSize(width: 100, height: 100)
            ),
            .zero
        )
    }

    func testDisplayRectIsZeroForZeroContainer() {
        XCTAssertEqual(
            PoseCoordinateTransform.displayRect(
                imageSize: CGSize(width: 100, height: 100),
                in: .zero
            ),
            .zero
        )
    }

    // MARK: - viewPoint

    func testViewPointAtImageOriginMapsToBottomLeftOfDisplayRect() {
        // Vision origin (0, 0) is the bottom-left of the image. With a
        // display rect of (10, 20)…(110, 220), bottom-left is (10, 220).
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        let result = PoseCoordinateTransform.viewPoint(
            normalizedImagePoint: CGPoint(x: 0, y: 0),
            displayRect: rect
        )
        XCTAssertEqual(result.x, 10, accuracy: accuracy)
        XCTAssertEqual(result.y, 220, accuracy: accuracy)
    }

    func testViewPointAtTopRightOfImageMapsToTopRightOfDisplayRect() {
        // Vision (1, 1) is the top-right; same as view top-right after flip.
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        let result = PoseCoordinateTransform.viewPoint(
            normalizedImagePoint: CGPoint(x: 1, y: 1),
            displayRect: rect
        )
        XCTAssertEqual(result.x, 110, accuracy: accuracy)
        XCTAssertEqual(result.y, 20, accuracy: accuracy)
    }

    func testViewPointAtCenterMapsToCenter() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 200)
        let result = PoseCoordinateTransform.viewPoint(
            normalizedImagePoint: CGPoint(x: 0.5, y: 0.5),
            displayRect: rect
        )
        XCTAssertEqual(result.x, 200, accuracy: accuracy)
        XCTAssertEqual(result.y, 100, accuracy: accuracy)
    }

    func testViewPointInLetterboxedDisplayRect() {
        // 16:9 source in a 1:1 container produced a rect at y=87.5,
        // height=225. A Vision point at (0.5, 0.5) — image center — should
        // land at the center of *that rect*, i.e. (200, 200).
        let imageSize = CGSize(width: 1600, height: 900)
        let container = CGSize(width: 400, height: 400)
        let rect = PoseCoordinateTransform.displayRect(
            imageSize: imageSize,
            in: container
        )
        let result = PoseCoordinateTransform.viewPoint(
            normalizedImagePoint: CGPoint(x: 0.5, y: 0.5),
            displayRect: rect
        )
        XCTAssertEqual(result.x, 200, accuracy: accuracy)
        XCTAssertEqual(result.y, 200, accuracy: accuracy)
    }
}
