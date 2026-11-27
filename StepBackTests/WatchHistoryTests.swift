@testable import StepBack
import XCTest

/// Counting views and ordering the Library's Recently Watched row.
final class WatchHistoryTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 3_600

    private struct Item: Equatable {
        let name: String
        var stats = WatchStats()
    }

    /// A clip watched once per entry in `daysAgo`, oldest view first.
    private func item(_ name: String, viewsDaysAgo daysAgo: [Double], now: Date) -> Item {
        var stats = WatchStats()
        for ago in daysAgo.sorted(by: >) {
            stats.recordView(at: now.addingTimeInterval(-ago * day))
        }
        return Item(name: name, stats: stats)
    }

    private func names(_ items: [Item], _ order: WatchOrder, now: Date, limit: Int = 20) -> [String] {
        WatchRanking.rank(items, by: order, now: now, limit: limit, stats: \.stats).map(\.name)
    }

    // MARK: - Counting

    func testNewStatsAreUnwatchedAndUnlisted() {
        let stats = WatchStats()
        XCTAssertFalse(stats.hasBeenWatched)
        XCTAssertFalse(stats.isListed)
        XCTAssertEqual(stats.heat(at: start), 0)
    }

    func testFirstViewCountsAndLists() {
        var stats = WatchStats()
        stats.recordView(at: start)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.lastWatchedAt, start)
        XCTAssertEqual(stats.heat(at: start), 1, accuracy: 1e-9)
        XCTAssertTrue(stats.isListed)
    }

    func testReopeningWithinTheSessionGapDoesNotAddAView() {
        var stats = WatchStats()
        stats.recordView(at: start)
        let soon = start.addingTimeInterval(WatchStats.sessionGap - 1)
        stats.recordView(at: soon)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.lastWatchedAt, soon, "the timestamp still moves on")
        XCTAssertEqual(
            stats.heat(at: soon),
            WatchStats.decay(over: WatchStats.sessionGap - 1),
            accuracy: 1e-9,
            "moving the timestamp neither adds heat nor undoes the decay"
        )
    }

    func testViewsAfterTheSessionGapEachCount() {
        var stats = WatchStats()
        stats.recordView(at: start)
        stats.recordView(at: start.addingTimeInterval(WatchStats.sessionGap))
        stats.recordView(at: start.addingTimeInterval(day))
        XCTAssertEqual(stats.count, 3)
    }

    func testHeatHalvesEveryHalfLife() {
        var stats = WatchStats()
        stats.recordView(at: start)
        let later = start.addingTimeInterval(WatchStats.halfLife)
        XCTAssertEqual(stats.heat(at: later), 0.5, accuracy: 1e-9)
        stats.recordView(at: later)
        XCTAssertEqual(stats.heat(at: later), 1.5, accuracy: 1e-9)
    }

    func testClockGoingBackwardsDoesNotInflateHeat() {
        var stats = WatchStats()
        stats.recordView(at: start)
        XCTAssertEqual(stats.heat(at: start.addingTimeInterval(-day)), 1, accuracy: 1e-9)
    }

    // MARK: - Hiding

    func testHiddenClipLeavesTheRowButKeepsItsHistory() {
        var stats = WatchStats()
        stats.recordView(at: start)
        stats.hide(at: start.addingTimeInterval(60))
        XCTAssertFalse(stats.isListed)
        XCTAssertEqual(stats.count, 1)
    }

    func testWatchingAHiddenClipAgainBringsItBack() {
        var stats = WatchStats()
        stats.recordView(at: start)
        stats.hide(at: start.addingTimeInterval(60))
        // Even inside the session gap: the user chose to watch it again.
        stats.recordView(at: start.addingTimeInterval(120))
        XCTAssertTrue(stats.isListed)
        XCTAssertEqual(stats.count, 1)
        stats.recordView(at: start.addingTimeInterval(day))
        XCTAssertEqual(stats.count, 2)
    }

    // MARK: - Ranking

    func testUnwatchedAndHiddenClipsAreLeftOut() {
        let now = start
        var hidden = item("hidden", viewsDaysAgo: [1], now: now)
        hidden.stats.hide(at: now)
        let items = [Item(name: "never"), item("watched", viewsDaysAgo: [2], now: now), hidden]
        for order in WatchOrder.allCases {
            XCTAssertEqual(names(items, order, now: now), ["watched"], "\(order)")
        }
    }

    func testRecentOrdersByLastWatched() {
        let now = start
        let items = [
            item("old-favourite", viewsDaysAgo: [30, 20, 10, 9, 8], now: now),
            item("yesterday", viewsDaysAgo: [1], now: now),
            item("today", viewsDaysAgo: [0], now: now),
        ]
        XCTAssertEqual(names(items, .recent, now: now), ["today", "yesterday", "old-favourite"])
    }

    func testMostWatchedOrdersByCountThenRecency() {
        let now = start
        let items = [
            item("twice-old", viewsDaysAgo: [40, 30], now: now),
            item("once", viewsDaysAgo: [0], now: now),
            item("five", viewsDaysAgo: [50, 40, 30, 20, 10], now: now),
            item("twice-new", viewsDaysAgo: [3, 2], now: now),
        ]
        XCTAssertEqual(names(items, .mostWatched, now: now), ["five", "twice-new", "twice-old", "once"])
    }

    func testSmartFavoursRegularRecentPractice() {
        let now = start
        let items = [
            // Hammered last spring, untouched since.
            item("stale-staple", viewsDaysAgo: Array(stride(from: 120.0, to: 100, by: -1)), now: now),
            // Opened once, just now.
            item("one-off", viewsDaysAgo: [0], now: now),
            // Practised every few days this month.
            item("current-routine", viewsDaysAgo: [12, 9, 6, 3, 1], now: now),
        ]
        XCTAssertEqual(names(items, .smart, now: now), ["current-routine", "one-off", "stale-staple"])
        XCTAssertEqual(names(items, .mostWatched, now: now).first, "stale-staple")
        XCTAssertEqual(names(items, .recent, now: now).first, "one-off")
    }

    func testRankingIsStableForTies() {
        let now = start
        let items = ["a", "b", "c"].map { item($0, viewsDaysAgo: [1], now: now) }
        for order in WatchOrder.allCases {
            XCTAssertEqual(names(items, order, now: now), ["a", "b", "c"], "\(order)")
        }
    }

    func testRankingHonoursTheLimit() {
        let now = start
        let items = (0..<30).map { item("clip\($0)", viewsDaysAgo: [Double($0)], now: now) }
        XCTAssertEqual(names(items, .recent, now: now, limit: 3), ["clip0", "clip1", "clip2"])
        XCTAssertEqual(WatchRanking.rank(items, by: .smart, now: now, stats: \.stats).count, WatchRanking.defaultLimit)
        XCTAssertTrue(names(items, .recent, now: now, limit: -1).isEmpty)
    }

    // MARK: - Model bridge

    @MainActor
    func testDanceClipRoundTripsWatchStats() {
        let clip = DanceClip(title: "Clip", assetIdentifier: "A")
        var stats = clip.watchStats
        stats.recordView(at: start)
        stats.hide(at: start.addingTimeInterval(1))
        clip.watchStats = stats
        XCTAssertEqual(clip.watchCount, 1)
        XCTAssertEqual(clip.lastWatchedAt, start)
        XCTAssertEqual(clip.watchHeat, 1, accuracy: 1e-9)
        XCTAssertEqual(clip.hiddenFromRecentsAt, start.addingTimeInterval(1))
        XCTAssertEqual(clip.watchStats, stats)
    }
}
