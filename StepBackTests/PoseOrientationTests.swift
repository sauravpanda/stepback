@testable import StepBack
import CoreGraphics
import ImageIO
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
        let t = CGAffineTransform(rotationAngle: .pi / 2)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: t),
            .right
        )
    }

    func testRotate180IsDown() {
        let t = CGAffineTransform(rotationAngle: .pi)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: t),
            .down
        )
    }

    func testRotateNegative180IsDown() {
        // atan2 returns -π for a 180° rotation when entered as -π.
        // Both should map to .down.
        let t = CGAffineTransform(rotationAngle: -.pi)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: t),
            .down
        )
    }

    func testRotate90CounterclockwiseIsLeft() {
        let t = CGAffineTransform(rotationAngle: -.pi / 2)
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: t),
            .left
        )
    }

    func testWeirdTransformFallsBackToUp() {
        // A non-90° rotation isn't something we expect from AVAsset's
        // preferredTransform, but if we ever get one the pipeline should
        // degrade gracefully — Vision still mostly works on .up sources.
        let t = CGAffineTransform(rotationAngle: .pi / 3)  // 60°
        XCTAssertEqual(
            CGImagePropertyOrientation(transform: t),
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
