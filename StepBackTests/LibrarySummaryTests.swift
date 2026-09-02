@testable import StepBack
import XCTest

/// The "12 videos · 1h 23m" line under the library title.
final class LibrarySummaryTests: XCTestCase {

    // MARK: - videoCount

    func testCountPluralisesOnTheTotal() {
        XCTAssertEqual(LibraryFormatter.videoCount(shown: 1, total: 1), "1 video")
        XCTAssertEqual(LibraryFormatter.videoCount(shown: 12, total: 12), "12 videos")
        XCTAssertEqual(LibraryFormatter.videoCount(shown: 0, total: 0), "0 videos")
    }

    func testCountShowsTheFilteredShareWhenSomeAreHidden() {
        XCTAssertEqual(LibraryFormatter.videoCount(shown: 4, total: 12), "4 of 12 videos")
        XCTAssertEqual(LibraryFormatter.videoCount(shown: 0, total: 3), "0 of 3 videos")
    }

    // MARK: - totalDuration

    func testTotalDurationPicksTheCoarsestUsefulUnit() {
        XCTAssertEqual(LibraryFormatter.totalDuration(45), "45s")
        XCTAssertEqual(LibraryFormatter.totalDuration(23 * 60 + 10), "23m")
        XCTAssertEqual(LibraryFormatter.totalDuration(3_600 + 23 * 60), "1h 23m")
        XCTAssertEqual(LibraryFormatter.totalDuration(2 * 3_600), "2h 0m")
    }

    func testTotalDurationIsNilWhenThereIsNothingToReport() {
        XCTAssertNil(LibraryFormatter.totalDuration(0))
        XCTAssertNil(LibraryFormatter.totalDuration(0.4))
        XCTAssertNil(LibraryFormatter.totalDuration(-10))
        XCTAssertNil(LibraryFormatter.totalDuration(.nan))
        XCTAssertNil(LibraryFormatter.totalDuration(.infinity))
    }

    // MARK: - summary

    func testSummaryJoinsCountAndDuration() {
        XCTAssertEqual(
            LibraryFormatter.summary(shown: 12, total: 12, seconds: 3_600 + 23 * 60),
            "12 videos · 1h 23m"
        )
        XCTAssertEqual(
            LibraryFormatter.summary(shown: 4, total: 12, seconds: 22 * 60),
            "4 of 12 videos · 22m"
        )
    }

    func testSummaryLeavesOutADurationOfNothing() {
        // Clips imported before their length was known report 0 seconds;
        // "3 videos · 0s" would look like a bug.
        XCTAssertEqual(LibraryFormatter.summary(shown: 3, total: 3, seconds: 0), "3 videos")
    }
}
