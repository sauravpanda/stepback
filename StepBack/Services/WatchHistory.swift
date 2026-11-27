import Foundation

/// How a clip has been watched: how often, how lately, and how "hot" it is
/// right now. A value type so the counting and ranking rules can be tested
/// without a model container; `DanceClip.watchStats` reads and writes it
/// through the stored columns.
///
/// `heat` is a frecency score: every view adds 1, and the total halves
/// every `halfLife`. That keeps the whole viewing history in one number —
/// ten views spread over this month outrank ten views from last spring —
/// without storing a row per view.
struct WatchStats: Equatable {
    /// Meaningful views, ever. Survives being removed from the row.
    var count: Int = 0
    /// When the clip was last watched. Nil until the first counted view.
    var lastWatchedAt: Date?
    /// Decayed view score as of `lastWatchedAt`. Use `heat(at:)` to read it.
    var heat: Double = 0
    /// When the user removed the clip from Recently Watched. The clip comes
    /// back once it's watched again after this.
    var hiddenAt: Date?

    /// How long Practice has to stay open before a visit counts. Long
    /// enough that tapping in by mistake or swiping straight past doesn't.
    static let minimumViewSeconds: TimeInterval = 5
    /// Opening a clip again within this window is the same practice
    /// session: it refreshes `lastWatchedAt` but adds no view, so flipping
    /// back and forth between two clips doesn't run up their counts.
    static let sessionGap: TimeInterval = 10 * 60
    /// The time it takes a view's weight in `heat` to fall by half.
    static let halfLife: TimeInterval = 14 * 24 * 3_600

    var hasBeenWatched: Bool { lastWatchedAt != nil && count > 0 }

    /// Whether the clip belongs in the Recently Watched row.
    var isListed: Bool {
        guard hasBeenWatched, let lastWatchedAt else { return false }
        guard let hiddenAt else { return true }
        return lastWatchedAt > hiddenAt
    }

    /// `heat` decayed forward to `now`.
    func heat(at now: Date) -> Double {
        guard let lastWatchedAt else { return 0 }
        return heat * Self.decay(over: now.timeIntervalSince(lastWatchedAt))
    }

    /// Records a meaningful view at `now`.
    mutating func recordView(at now: Date) {
        if let lastWatchedAt, now.timeIntervalSince(lastWatchedAt) < Self.sessionGap, count > 0 {
            // Same session. Carry the heat forward so moving the timestamp
            // doesn't quietly undo the decay since the last real view.
            heat = heat(at: now)
            self.lastWatchedAt = max(lastWatchedAt, now)
            return
        }
        heat = heat(at: now) + 1
        count += 1
        lastWatchedAt = now
    }

    /// Takes the clip out of the row without forgetting how it was watched.
    mutating func hide(at now: Date) {
        hiddenAt = now
    }

    /// The fraction of weight left after `interval`. Negative intervals
    /// (a clock that moved backwards) leave the weight untouched.
    static func decay(over interval: TimeInterval) -> Double {
        guard interval > 0 else { return 1 }
        return pow(0.5, interval / halfLife)
    }
}

/// How the Recently Watched row is ordered.
enum WatchOrder: String, CaseIterable, Identifiable {
    /// A blend of how often and how lately: the decayed view score.
    case smart
    /// Most recently watched first.
    case recent
    /// Most views first.
    case mostWatched

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smart: "Smart"
        case .recent: "Recent"
        case .mostWatched: "Most watched"
        }
    }

    var systemImage: String {
        switch self {
        case .smart: "sparkles"
        case .recent: "clock"
        case .mostWatched: "chart.bar"
        }
    }
}

enum WatchRanking {
    /// Enough to hold the couple of dozen clips that actually get rewatched.
    static let defaultLimit = 20

    /// The listed items, best first, at most `limit` of them. Ties fall back
    /// to recency, then to the input order, so the row doesn't shuffle
    /// between renders.
    static func rank<Item>(
        _ items: [Item],
        by order: WatchOrder,
        now: Date = Date(),
        limit: Int = defaultLimit,
        stats: (Item) -> WatchStats
    ) -> [Item] {
        let listed = items.enumerated().compactMap { index, item -> Entry<Item>? in
            let itemStats = stats(item)
            guard itemStats.isListed, let last = itemStats.lastWatchedAt else { return nil }
            return Entry(item: item, index: index, stats: itemStats, last: last, heat: itemStats.heat(at: now))
        }
        return listed
            .sorted { lhs, rhs in isOrdered(lhs, before: rhs, by: order) }
            .prefix(max(0, limit))
            .map(\.item)
    }

    private struct Entry<Item> {
        let item: Item
        let index: Int
        let stats: WatchStats
        let last: Date
        let heat: Double
    }

    private static func isOrdered<Item>(_ lhs: Entry<Item>, before rhs: Entry<Item>, by order: WatchOrder) -> Bool {
        switch order {
        case .smart where lhs.heat != rhs.heat:
            return lhs.heat > rhs.heat
        case .mostWatched where lhs.stats.count != rhs.stats.count:
            return lhs.stats.count > rhs.stats.count
        default:
            break
        }
        if lhs.last != rhs.last {
            return lhs.last > rhs.last
        }
        return lhs.index < rhs.index
    }
}
