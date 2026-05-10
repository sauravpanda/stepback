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

    // MARK: - shortDate

    /// Force en_US_POSIX so localised separators (",", " de ", non-breaking
    /// spaces) don't make these assertions environment-dependent.
    private static func enUSPosix() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        return Self.enUSPosix().date(from: comp)!
    }

    func testShortDateOmitsYearWhenSameAsNow() {
        let cal = Self.enUSPosix()
        let now = makeDate(year: 2026, month: 5, day: 9)
        let date = makeDate(year: 2026, month: 3, day: 11)

        // Always contains the month abbreviation and day; never the year.
        let formatted = LibraryFormatter.shortDate(date, now: now, calendar: cal)
        XCTAssertTrue(formatted.contains("Mar"))
        XCTAssertTrue(formatted.contains("11"))
        XCTAssertFalse(formatted.contains("2026"))
    }

    func testShortDateIncludesYearWhenDifferentFromNow() {
        let cal = Self.enUSPosix()
        let now = makeDate(year: 2026, month: 5, day: 9)
        let date = makeDate(year: 2024, month: 3, day: 11)

        let formatted = LibraryFormatter.shortDate(date, now: now, calendar: cal)
        XCTAssertTrue(formatted.contains("Mar"))
        XCTAssertTrue(formatted.contains("11"))
        XCTAssertTrue(formatted.contains("2024"))
    }
}
