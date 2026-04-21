@testable import StepBack
import XCTest

final class SpeedFormatterTests: XCTestCase {

    func testPillFormatting() {
        XCTAssertEqual(SpeedFormatter.pill(0.25), "0.25×")
        XCTAssertEqual(SpeedFormatter.pill(0.5), "0.5×")
        XCTAssertEqual(SpeedFormatter.pill(0.75), "0.75×")
        XCTAssertEqual(SpeedFormatter.pill(1), "1×")
        XCTAssertEqual(SpeedFormatter.pill(1.25), "1.25×")
        XCTAssertEqual(SpeedFormatter.pill(1.5), "1.5×")
    }

    func testEqualsTolerance() {
        XCTAssertTrue(SpeedFormatter.equals(1.0, 1.0))
        XCTAssertTrue(SpeedFormatter.equals(0.5, 0.5 + 1e-9))
        XCTAssertFalse(SpeedFormatter.equals(0.5, 0.75))
    }

    func testTimestampZero() {
        XCTAssertEqual(SpeedFormatter.timestamp(0), "0:00.00")
    }

    func testTimestampUnderAMinute() {
        XCTAssertEqual(SpeedFormatter.timestamp(12.34), "0:12.34")
    }

    func testTimestampOverAMinute() {
        XCTAssertEqual(SpeedFormatter.timestamp(83.56), "1:23.56")
    }

    func testTimestampNonFiniteOrNegative() {
        XCTAssertEqual(SpeedFormatter.timestamp(.infinity), "--:--")
        XCTAssertEqual(SpeedFormatter.timestamp(.nan), "--:--")
        XCTAssertEqual(SpeedFormatter.timestamp(-1), "--:--")
    }
}
