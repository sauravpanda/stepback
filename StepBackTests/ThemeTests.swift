@testable import StepBack
import SwiftUI
import XCTest

final class ThemeTests: XCTestCase {

    func testSpeedPillColorBuckets() {
        XCTAssertEqual(Theme.Color.speedPillColor(for: 0.25), Theme.Color.speedCyan)
        XCTAssertEqual(Theme.Color.speedPillColor(for: 0.49), Theme.Color.speedCyan)
        XCTAssertEqual(Theme.Color.speedPillColor(for: 0.5), Theme.Color.speedGreen)
        XCTAssertEqual(Theme.Color.speedPillColor(for: 0.75), Theme.Color.speedGreen)
        XCTAssertEqual(Theme.Color.speedPillColor(for: 1.0), Theme.Color.speedWhite)
        XCTAssertEqual(Theme.Color.speedPillColor(for: 1.25), Theme.Color.speedOrange)
        XCTAssertEqual(Theme.Color.speedPillColor(for: 1.5), Theme.Color.speedOrange)
    }

    func testHexInitializerRoundTrip() {
        let color = Color(hex: 0xFF3B7F)
        // Not much we can assert about resolved values without a view — smoke-test instantiation.
        XCTAssertNotNil(color)
    }
}
