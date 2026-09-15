@testable import StepBack
import XCTest

final class VideoFrameTests: XCTestCase {

    private let phone = CGSize(width: 393, height: 500)

    func testLandscapeVideoSitsInABandAcrossTheMiddle() {
        let rect = VideoFrame.aspectFitRect(videoSize: CGSize(width: 1_920, height: 1_080), in: phone)
        XCTAssertEqual(rect.width, 393, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 393 * 9 / 16, accuracy: 1e-9)
        XCTAssertEqual(rect.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.midY, 250, accuracy: 1e-9, "centred vertically")
    }

    func testPortraitVideoFillsTheHeight() {
        let rect = VideoFrame.aspectFitRect(videoSize: CGSize(width: 1_080, height: 1_920), in: phone)
        XCTAssertEqual(rect.height, 500, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 500 * 9 / 16, accuracy: 1e-9)
        XCTAssertEqual(rect.midX, 196.5, accuracy: 1e-9, "centred horizontally")
    }

    func testAQuarterTurnSwapsTheAxes() {
        let landscape = CGSize(width: 1_920, height: 1_080)
        let turned = VideoFrame.aspectFitRect(videoSize: landscape, in: phone, quarterTurns: 1)
        let asPortrait = VideoFrame.aspectFitRect(videoSize: CGSize(width: 1_080, height: 1_920), in: phone)
        XCTAssertEqual(turned, asPortrait)
        XCTAssertEqual(
            VideoFrame.aspectFitRect(videoSize: landscape, in: phone, quarterTurns: 2),
            VideoFrame.aspectFitRect(videoSize: landscape, in: phone)
        )
        XCTAssertEqual(
            VideoFrame.aspectFitRect(videoSize: landscape, in: phone, quarterTurns: -1),
            asPortrait,
            "turning the other way still swaps"
        )
    }

    func testUnknownSizeFallsBackToTheWholeContainer() {
        XCTAssertEqual(
            VideoFrame.aspectFitRect(videoSize: .zero, in: phone),
            CGRect(origin: .zero, size: phone)
        )
    }

    func testOrientedSizeAppliesTheTransform() {
        // A portrait phone recording: 1920×1080 buffer, rotated 90°.
        let rotated = CGAffineTransform(rotationAngle: .pi / 2)
        let size = VideoFrame.orientedSize(naturalSize: CGSize(width: 1_920, height: 1_080), preferredTransform: rotated)
        XCTAssertEqual(size.width, 1_080, accuracy: 1e-6)
        XCTAssertEqual(size.height, 1_920, accuracy: 1e-6)

        let upright = VideoFrame.orientedSize(naturalSize: CGSize(width: 1_920, height: 1_080), preferredTransform: .identity)
        XCTAssertEqual(upright, CGSize(width: 1_920, height: 1_080))
    }
}
