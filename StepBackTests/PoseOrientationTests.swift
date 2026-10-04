import CoreGraphics
import ImageIO
@testable import StepBack
import XCTest

final class PoseOrientationTests: XCTestCase {

    // MARK: - Init from CGAffineTransform

    func testIdentityTransformIsUp() {
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: .identity),
            .up
        )
    }

    func testRotate90ClockwiseIsRight() {
        // iPhone-shot portrait videos land here. Storage buffer is
        // landscape, displayed portrait by rotating 90° CW.
        let transform = CGAffineTransform(rotationAngle: .pi / 2)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: transform),
            .right
        )
    }

    func testRotate180IsDown() {
        let transform = CGAffineTransform(rotationAngle: .pi)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: transform),
            .down
        )
    }

    func testRotateNegative180IsDown() {
        // atan2 returns -π for a 180° rotation when entered as -π.
        // Both should map to .down.
        let transform = CGAffineTransform(rotationAngle: -.pi)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: transform),
            .down
        )
    }

    func testRotate90CounterclockwiseIsLeft() {
        let transform = CGAffineTransform(rotationAngle: -.pi / 2)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: transform),
            .left
        )
    }

    func testWeirdTransformFallsBackToUp() {
        // A non-90° rotation isn't something we expect from AVAsset's
        // preferredTransform, but if we ever get one the pipeline should
        // degrade gracefully — Vision still mostly works on .up sources.
        let transform = CGAffineTransform(rotationAngle: .pi / 3)  // 60°
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: transform),
            .up
        )
    }

    // MARK: - Axis swap

    func testSwapsAxesIsTrueForLeftAndRight() {
        XCTAssertTrue(CGImagePropertyOrientation.left.swapsAxes)
        XCTAssertTrue(CGImagePropertyOrientation.right.swapsAxes)
        XCTAssertTrue(CGImagePropertyOrientation.leftMirrored.swapsAxes)
        XCTAssertTrue(CGImagePropertyOrientation.rightMirrored.swapsAxes)
    }

    func testSwapsAxesIsFalseForUpAndDown() {
        XCTAssertFalse(CGImagePropertyOrientation.up.swapsAxes)
        XCTAssertFalse(CGImagePropertyOrientation.down.swapsAxes)
        XCTAssertFalse(CGImagePropertyOrientation.upMirrored.swapsAxes)
        XCTAssertFalse(CGImagePropertyOrientation.downMirrored.swapsAxes)
    }
}
