@testable import StepBack
import XCTest

final class StepTimingTests: XCTestCase {

    // MARK: - StepRating

    func testRatingBucketsByAbsoluteOffset() {
        XCTAssertEqual(StepRating(offsetMs: 0), .perfect)
        XCTAssertEqual(StepRating(offsetMs: 49.9), .perfect)
        XCTAssertEqual(StepRating(offsetMs: -49.9), .perfect)
        XCTAssertEqual(StepRating(offsetMs: 50), .good)
        XCTAssertEqual(StepRating(offsetMs: -119.9), .good)
        XCTAssertEqual(StepRating(offsetMs: 120), .off)
        XCTAssertEqual(StepRating(offsetMs: -500), .off)
    }

    // MARK: - StepTimingStats

    func testAverageNilOnEmpty() {
        XCTAssertNil(StepTimingStats.averageOffsetMs([]))
    }

    func testAverageIsArithmeticMean() {
        let taps = [
            StepTap(time: 1, offsetMs: -40),
            StepTap(time: 2, offsetMs: 60),
            StepTap(time: 3, offsetMs: -20)
        ]
        XCTAssertEqual(StepTimingStats.averageOffsetMs(taps) ?? 0, 0, accuracy: 1e-6)
    }

    func testAverageNegativeForEarlyBias() {
        let taps = [
            StepTap(time: 1, offsetMs: -80),
            StepTap(time: 2, offsetMs: -40)
        ]
        XCTAssertEqual(StepTimingStats.averageOffsetMs(taps) ?? 0, -60, accuracy: 1e-6)
    }

    func testBucketCountsDistributesEveryTap() {
        let taps = [
            StepTap(time: 1, offsetMs: 10),     // perfect
            StepTap(time: 2, offsetMs: -45),    // perfect
            StepTap(time: 3, offsetMs: 80),     // good
            StepTap(time: 4, offsetMs: -115),   // good
            StepTap(time: 5, offsetMs: 150),    // off
            StepTap(time: 6, offsetMs: -999)    // off
        ]
        let counts = StepTimingStats.bucketCounts(taps)
        XCTAssertEqual(counts.perfect, 2)
        XCTAssertEqual(counts.good, 2)
        XCTAssertEqual(counts.off, 2)
        XCTAssertEqual(counts.total, taps.count)
    }
}
