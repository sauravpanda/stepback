@testable import StepBack
import XCTest

final class TrimStorageTests: XCTestCase {

    func testMakeFileNameRoundTripsThroughBounds() {
        let name = TrimStorage.makeFileName(start: 5.25, end: 12.5)
        let bounds = TrimStorage.bounds(fromName: name)
        XCTAssertEqual(bounds?.start ?? -1, 5.25, accuracy: 0.001)
        XCTAssertEqual(bounds?.end ?? -1, 12.5, accuracy: 0.001)
    }

    func testMakeFileNameUsesMillisecondPrecision() {
        let name = TrimStorage.makeFileName(start: 3.219, end: 5.0)
        // 3.219s → 3219 ms → 3.219 on the way back (ms-resolution).
        let bounds = TrimStorage.bounds(fromName: name)
        XCTAssertEqual(bounds?.start ?? -1, 3.219, accuracy: 0.0005)
    }

    func testMakeFileNameHasMovExtension() {
        XCTAssertTrue(TrimStorage.makeFileName(start: 0, end: 1).hasSuffix(".mov"))
    }

    func testLegacyNameHasNoBounds() {
        XCTAssertNil(TrimStorage.bounds(fromName: "\(UUID().uuidString).mov"))
    }

    func testMalformedNameHasNoBounds() {
        XCTAssertNil(TrimStorage.bounds(fromName: "trim-abc__notanumber__500.mov"))
        XCTAssertNil(TrimStorage.bounds(fromName: "trim-abc__500.mov"))   // only one number
        XCTAssertNil(TrimStorage.bounds(fromName: "plain.mov"))
    }

    func testBoundsRejectsNonIncreasingRange() {
        // end must be strictly after start.
        let name = "trim-x__5000__5000.mov"
        XCTAssertNil(TrimStorage.bounds(fromName: name))
    }

    func testBoundsParsesAWellFormedName() {
        let bounds = TrimStorage.bounds(fromName: "trim-DEADBEEF__2000__9000.mov")
        XCTAssertEqual(bounds?.start ?? -1, 2.0, accuracy: 0.001)
        XCTAssertEqual(bounds?.end ?? -1, 9.0, accuracy: 0.001)
    }
}
