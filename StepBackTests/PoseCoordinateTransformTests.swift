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

    // MARK: - unzoomedFraction

    func testUnzoomedFractionWithoutZoomIsLocationOverSize() {
        let f = PoseCoordinateTransform.unzoomedFraction(
            location: CGPoint(x: 100, y: 200),
            containerSize: CGSize(width: 400, height: 400),
            scale: 1,
            offset: .zero
        )
        XCTAssertEqual(f.x, 0.25, accuracy: accuracy)
        XCTAssertEqual(f.y, 0.5, accuracy: accuracy)
    }

    func testUnzoomedFractionUndoesCenterScale() {
        // At 2× zoom about center, a tap at the exact center still maps to
        // the content center (0.5, 0.5).
        let f = PoseCoordinateTransform.unzoomedFraction(
            location: CGPoint(x: 200, y: 200),
            containerSize: CGSize(width: 400, height: 400),
            scale: 2,
            offset: .zero
        )
        XCTAssertEqual(f.x, 0.5, accuracy: accuracy)
        XCTAssertEqual(f.y, 0.5, accuracy: accuracy)
    }

    func testUnzoomedFractionUndoesOffset() {
        // Pan the content right by 50; a tap at center now corresponds to a
        // content point left of center.
        let f = PoseCoordinateTransform.unzoomedFraction(
            location: CGPoint(x: 200, y: 200),
            containerSize: CGSize(width: 400, height: 400),
            scale: 1,
            offset: CGSize(width: 50, height: 0)
        )
        XCTAssertEqual(f.x, (200.0 - 50.0) / 400.0, accuracy: accuracy)  // 0.375
        XCTAssertEqual(f.y, 0.5, accuracy: accuracy)
    }

    func testUnzoomedFractionZeroContainerIsZero() {
        let f = PoseCoordinateTransform.unzoomedFraction(
            location: CGPoint(x: 10, y: 10),
            containerSize: .zero,
            scale: 1,
            offset: .zero
        )
        XCTAssertEqual(f, .zero)
    }

    // MARK: - normalizedImagePoint (inverse of viewPoint)

    func testNormalizedImagePointRoundTripsViewPoint() {
        // viewPoint maps image → unit container fraction; the inverse should
        // recover the original image point.
        let imageSize = CGSize(width: 1600, height: 900)
        let unitRect = PoseCoordinateTransform.displayRect(
            imageSize: imageSize,
            in: CGSize(width: 1, height: 1)
        )
        let original = CGPoint(x: 0.3, y: 0.7)
        let fraction = PoseCoordinateTransform.viewPoint(
            normalizedImagePoint: original,
            displayRect: unitRect
        )
        let recovered = PoseCoordinateTransform.normalizedImagePoint(
            containerFraction: fraction,
            unitDisplayRect: unitRect
        )
        XCTAssertEqual(recovered?.x ?? -1, original.x, accuracy: accuracy)
        XCTAssertEqual(recovered?.y ?? -1, original.y, accuracy: accuracy)
    }

    func testNormalizedImagePointNilOutsideLetterbox() {
        // 16:9 in unit square letterboxes top/bottom (rect.minY≈0.219). A
        // touch up at y=0.05 is in the black bar → nil.
        let unitRect = PoseCoordinateTransform.displayRect(
            imageSize: CGSize(width: 1600, height: 900),
            in: CGSize(width: 1, height: 1)
        )
        let recovered = PoseCoordinateTransform.normalizedImagePoint(
            containerFraction: CGPoint(x: 0.5, y: 0.05),
            unitDisplayRect: unitRect
        )
        XCTAssertNil(recovered)
    }

    // MARK: - unrotatedFraction (touch → pre-rotation content)

    func testUnrotatedFractionIdentityAtZeroTurns() {
        let f = CGPoint(x: 0.2, y: 0.7)
        XCTAssertEqual(PoseCoordinateTransform.unrotatedFraction(f, quarterTurns: 0), f)
    }

    func testUnrotatedFractionUndoes90Clockwise() {
        // Rotating content 90° CW sends content (x, y) → display (1−y, x).
        // The inverse must send display (0.3, 0.2) back to content (0.2, 0.7).
        let recovered = PoseCoordinateTransform.unrotatedFraction(
            CGPoint(x: 0.3, y: 0.2),
            quarterTurns: 1
        )
        XCTAssertEqual(recovered.x, 0.2, accuracy: accuracy)
        XCTAssertEqual(recovered.y, 0.7, accuracy: accuracy)
    }

    func testUnrotatedFractionUndoes180() {
        let recovered = PoseCoordinateTransform.unrotatedFraction(
            CGPoint(x: 0.3, y: 0.2),
            quarterTurns: 2
        )
        XCTAssertEqual(recovered.x, 0.7, accuracy: accuracy)
        XCTAssertEqual(recovered.y, 0.8, accuracy: accuracy)
    }

    func testUnrotatedFractionUndoes270Clockwise() {
        // 270° CW ≡ 90° CCW: content (x, y) → display (y, 1−x); inverse of
        // display (0.3, 0.2) is content (1−0.2, 0.3) = (0.8, 0.3).
        let recovered = PoseCoordinateTransform.unrotatedFraction(
            CGPoint(x: 0.3, y: 0.2),
            quarterTurns: 3
        )
        XCTAssertEqual(recovered.x, 0.8, accuracy: accuracy)
        XCTAssertEqual(recovered.y, 0.3, accuracy: accuracy)
    }

    func testUnrotatedFractionRoundTripsEveryQuarterTurn() {
        // Forward rotation (CW by n quarter-turns) then the inverse must be
        // the identity for all four states.
        let original = CGPoint(x: 0.15, y: 0.85)
        for turns in 0...3 {
            var rotated = original
            for _ in 0..<turns {
                rotated = CGPoint(x: 1 - rotated.y, y: rotated.x)  // one 90° CW
            }
            let recovered = PoseCoordinateTransform.unrotatedFraction(rotated, quarterTurns: turns)
            XCTAssertEqual(recovered.x, original.x, accuracy: accuracy, "turns=\(turns)")
            XCTAssertEqual(recovered.y, original.y, accuracy: accuracy, "turns=\(turns)")
        }
    }

    func testUnrotatedFractionNormalizesOutOfRangeTurns() {
        let f = CGPoint(x: 0.3, y: 0.2)
        XCTAssertEqual(
            PoseCoordinateTransform.unrotatedFraction(f, quarterTurns: 5),
            PoseCoordinateTransform.unrotatedFraction(f, quarterTurns: 1)
        )
        XCTAssertEqual(
            PoseCoordinateTransform.unrotatedFraction(f, quarterTurns: -1),
            PoseCoordinateTransform.unrotatedFraction(f, quarterTurns: 3)
        )
    }
}
