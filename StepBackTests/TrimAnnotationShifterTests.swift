@testable import StepBack
import XCTest

final class TrimAnnotationShifterTests: XCTestCase {

    // MARK: - Points

    func testShiftPointInsideRangeRebases() {
        XCTAssertEqual(
            TrimAnnotationShifter.shiftPoint(7, trimStart: 5, trimEnd: 12),
            2
        )
    }

    func testShiftPointOutsideRangeIsDropped() {
        XCTAssertNil(TrimAnnotationShifter.shiftPoint(2, trimStart: 5, trimEnd: 12))
        XCTAssertNil(TrimAnnotationShifter.shiftPoint(15, trimStart: 5, trimEnd: 12))
    }

    func testShiftPointAtBoundariesKeptAndZeroed() {
        XCTAssertEqual(TrimAnnotationShifter.shiftPoint(5, trimStart: 5, trimEnd: 12), 0)
        XCTAssertEqual(TrimAnnotationShifter.shiftPoint(12, trimStart: 5, trimEnd: 12), 7)
    }

    // MARK: - Ranges

    func testShiftRangeFullyInsideRebasesWithoutClamping() {
        let result = TrimAnnotationShifter.shiftRange(
            start: 6, end: 10, trimStart: 5, trimEnd: 12
        )
        XCTAssertEqual(result, .init(start: 1, end: 5))
    }

    func testShiftRangeFullyOutsideIsDropped() {
        XCTAssertNil(
            TrimAnnotationShifter.shiftRange(
                start: 1, end: 4, trimStart: 5, trimEnd: 12
            )
        )
        XCTAssertNil(
            TrimAnnotationShifter.shiftRange(
                start: 13, end: 18, trimStart: 5, trimEnd: 12
            )
        )
    }

    func testShiftRangeStraddlingStartIsClamped() {
        let result = TrimAnnotationShifter.shiftRange(
            start: 3, end: 8, trimStart: 5, trimEnd: 12
        )
        XCTAssertEqual(result, .init(start: 0, end: 3))
    }

    func testShiftRangeStraddlingEndIsClamped() {
        let result = TrimAnnotationShifter.shiftRange(
            start: 9, end: 15, trimStart: 5, trimEnd: 12
        )
        XCTAssertEqual(result, .init(start: 4, end: 7))
    }

    func testShiftRangeCollapsingBelowMinimumIsDropped() {
        // Pre-trim range [4.99, 5.0]: only the last 0.01s overlaps the kept
        // window — too small to keep as a meaningful segment.
        XCTAssertNil(
            TrimAnnotationShifter.shiftRange(
                start: 4.99, end: 5.0, trimStart: 5, trimEnd: 12
            )
        )
    }

    func testShiftRangeWithInvertedInputReturnsNil() {
        XCTAssertNil(
            TrimAnnotationShifter.shiftRange(
                start: 8, end: 6, trimStart: 5, trimEnd: 12
            )
        )
    }

    // MARK: - Beat times

    func testShiftBeatTimesDropsOutOfWindowAndRebases() {
        let original: [Double] = [0.5, 2.0, 5.0, 6.5, 9.0, 13.0]
        let shifted = TrimAnnotationShifter.shiftBeatTimes(
            original, trimStart: 2, trimEnd: 10
        )
        XCTAssertEqual(shifted, [0.0, 3.0, 4.5, 7.0])
    }

    func testShiftBeatTimesEmptyArrayReturnsEmpty() {
        XCTAssertTrue(
            TrimAnnotationShifter.shiftBeatTimes([], trimStart: 0, trimEnd: 1).isEmpty
        )
    }
}
