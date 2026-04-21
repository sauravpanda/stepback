@testable import StepBack
import XCTest

final class LibraryFormatterTests: XCTestCase {

    func testDurationZeroOrNegativeReturnsPlaceholder() {
        XCTAssertEqual(LibraryFormatter.duration(0), "--:--")
        XCTAssertEqual(LibraryFormatter.duration(-5), "--:--")
    }

    func testDurationNonFiniteReturnsPlaceholder() {
        XCTAssertEqual(LibraryFormatter.duration(.infinity), "--:--")
        XCTAssertEqual(LibraryFormatter.duration(.nan), "--:--")
    }

    func testDurationUnderAMinute() {
        XCTAssertEqual(LibraryFormatter.duration(1), "0:01")
        XCTAssertEqual(LibraryFormatter.duration(45), "0:45")
        XCTAssertEqual(LibraryFormatter.duration(59.4), "0:59")
    }

    func testDurationMultiMinuteRoundsToNearestSecond() {
        XCTAssertEqual(LibraryFormatter.duration(60), "1:00")
        XCTAssertEqual(LibraryFormatter.duration(83.6), "1:24")
        XCTAssertEqual(LibraryFormatter.duration(3 * 60 + 7.5), "3:08")
    }
}
