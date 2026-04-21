@testable import StepBack
import XCTest

final class AutoTagServiceTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = hour
        comp.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: comp)!
    }

    func testEmptyReturnsEmpty() {
        XCTAssertTrue(AutoTagService.cluster(dates: []).isEmpty)
    }

    func testSingleDateYieldsOneCluster() {
        let dates = [date(2026, 4, 20)]
        let clusters = AutoTagService.cluster(dates: dates)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].indices, [0])
        XCTAssertTrue(clusters[0].tagName.hasPrefix("Event: "))
    }

    func testClipsSameDaySameCluster() {
        let dates = [
            date(2026, 4, 20, hour: 9),
            date(2026, 4, 20, hour: 18),
            date(2026, 4, 20, hour: 21)
        ]
        let clusters = AutoTagService.cluster(dates: dates)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].indices.count, 3)
    }

    func testGapOverTwentyFourHoursSplitsClusters() {
        let dates = [
            date(2026, 4, 20, hour: 9),
            // Exactly 25 hours later — past the 24h gap
            date(2026, 4, 21, hour: 10),
            date(2026, 4, 21, hour: 22)
        ]
        let clusters = AutoTagService.cluster(dates: dates)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].indices, [0])
        XCTAssertEqual(clusters[1].indices, [1, 2])
    }

    func testClusterIsIndexedBackToOriginalOrder() {
        // Out-of-order input: cluster() sorts internally but preserves original
        // indices so the caller can wire clips[index] back up.
        let dates = [
            date(2026, 4, 25, hour: 10), // index 0, later date
            date(2026, 4, 20, hour: 10)  // index 1, earlier date
        ]
        let clusters = AutoTagService.cluster(dates: dates)
        XCTAssertEqual(clusters.count, 2)
        // First cluster (by date) should reference the earlier clip, which is index 1
        XCTAssertEqual(clusters[0].indices, [1])
        XCTAssertEqual(clusters[1].indices, [0])
    }

    func testTagColorIsDeterministicPerName() {
        let first = AutoTagService.color(for: "Event: Apr 20, 2026")
        let second = AutoTagService.color(for: "Event: Apr 20, 2026")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            AutoTagService.color(for: "Event: Apr 20, 2026"),
            AutoTagService.color(for: "Event: Dec 31, 2099")
        )
    }
}
