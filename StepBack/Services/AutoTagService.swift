import Foundation

enum AutoTagService {

    /// 24 hours between consecutive clips ends a cluster and starts a new one.
    static let clusterGap: TimeInterval = 24 * 60 * 60

    /// Deterministic palette (hex strings matching Theme accents).
    private static let palette: [String] = [
        "#FF3B7F", "#5FE7FF", "#5FFFA8", "#FFA13B",
        "#C2A2FF", "#FFD93B", "#3BFF9E", "#FF6B9F"
    ]

    struct ClusterDescriptor: Equatable {
        /// Indexes back into the input array so the caller can wire clips up.
        let indices: [Int]
        let earliest: Date
        let tagName: String
        let colorHex: String
    }

    /// Pure clustering: sorts by date, groups by 24h gap, names each cluster
    /// "Event: MMM d, yyyy" from the earliest date. Stable color per name.
    static func cluster(dates: [Date], calendar: Calendar = .current) -> [ClusterDescriptor] {
        guard !dates.isEmpty else { return [] }

        let indexed = dates.enumerated().sorted { $0.element < $1.element }
        var clusters: [[(index: Int, date: Date)]] = []
        var current: [(index: Int, date: Date)] = []
        var previous: Date?

        for (index, date) in indexed {
            if let prev = previous, date.timeIntervalSince(prev) > clusterGap {
                clusters.append(current)
                current = []
            }
            current.append((index: index, date: date))
            previous = date
        }
        if !current.isEmpty {
            clusters.append(current)
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        formatter.dateFormat = "MMM d, yyyy"

        return clusters.map { group in
            let earliest = group.first?.date ?? Date()
            let tagName = "Event: \(formatter.string(from: earliest))"
            return ClusterDescriptor(
                indices: group.map(\.index),
                earliest: earliest,
                tagName: tagName,
                colorHex: color(for: tagName)
            )
        }
    }

    /// Deterministic color pick: hash the name modulo palette length.
    static func color(for name: String) -> String {
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}
