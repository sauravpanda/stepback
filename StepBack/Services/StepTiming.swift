import Foundation
import SwiftUI

struct StepTap: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let offsetMs: Double

    init(id: UUID = UUID(), time: Double, offsetMs: Double) {
        self.time = time
        self.offsetMs = offsetMs
    }
}

enum StepRating: Equatable {
    case perfect
    case good
    case off

    /// Buckets by absolute offset from the nearest beat:
    /// `<50ms` perfect, `<120ms` good, otherwise off.
    init(offsetMs: Double) {
        let magnitude = abs(offsetMs)
        if magnitude < 50 {
            self = .perfect
        } else if magnitude < 120 {
            self = .good
        } else {
            self = .off
        }
    }

    var color: Color {
        switch self {
        case .perfect: Color(hex: 0x5FFFA8)
        case .good: Color(hex: 0xFFD93B)
        case .off: Color(hex: 0xFF5F5F)
        }
    }

    var label: String {
        switch self {
        case .perfect: "Perfect"
        case .good: "Good"
        case .off: "Off"
        }
    }
}

struct BucketCounts: Equatable {
    var perfect: Int = 0
    var good: Int = 0
    var off: Int = 0

    var total: Int { perfect + good + off }
}

enum StepTimingStats {
    /// Arithmetic mean of the offsets in milliseconds. Negative = average
    /// tap is early; positive = average tap is late.
    static func averageOffsetMs(_ taps: [StepTap]) -> Double? {
        guard !taps.isEmpty else { return nil }
        let total = taps.reduce(0.0) { $0 + $1.offsetMs }
        return total / Double(taps.count)
    }

    /// Per-bucket count for quick glance stats.
    static func bucketCounts(_ taps: [StepTap]) -> BucketCounts {
        var counts = BucketCounts()
        for tap in taps {
            switch StepRating(offsetMs: tap.offsetMs) {
            case .perfect: counts.perfect += 1
            case .good: counts.good += 1
            case .off: counts.off += 1
            }
        }
        return counts
    }
}
