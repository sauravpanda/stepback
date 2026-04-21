import Foundation

/// Pure helpers for reasoning about a cached beat grid. All functions here
/// are value-in / value-out so they can be tested without an AVPlayer.
enum BeatGrid {

    /// Closest beat index to `time`. Returns `nil` if `beatTimes` is empty.
    static func nearestBeatIndex(to time: Double, in beatTimes: [Double]) -> Int? {
        guard !beatTimes.isEmpty else { return nil }
        // Binary search for the first index whose time >= target.
        var lower = 0
        var upper = beatTimes.count
        while lower < upper {
            let mid = (lower + upper) / 2
            if beatTimes[mid] < time { lower = mid + 1 } else { upper = mid }
        }
        let before = lower - 1
        let after = lower
        let beforeDiff = before >= 0 ? abs(time - beatTimes[before]) : .infinity
        let afterDiff = after < beatTimes.count ? abs(time - beatTimes[after]) : .infinity
        return beforeDiff <= afterDiff ? before : after
    }

    /// Signed offset in milliseconds from `time` to its nearest beat.
    /// Negative = early (tap came before the beat), positive = late.
    static func offsetMs(from time: Double, toNearestBeatIn beatTimes: [Double]) -> Double? {
        guard let idx = nearestBeatIndex(to: time, in: beatTimes) else { return nil }
        return (time - beatTimes[idx]) * 1_000
    }

    /// Indices of every downbeat, derived from a user-supplied anchor.
    /// Finds the beat nearest the anchor and every `beatsPerMeasure`-th beat
    /// before and after it.
    static func downbeatIndices(
        beatTimes: [Double],
        anchor: Double?,
        beatsPerMeasure: Int
    ) -> Set<Int> {
        guard let anchor, !beatTimes.isEmpty, beatsPerMeasure > 0,
              let nearest = nearestBeatIndex(to: anchor, in: beatTimes) else {
            return []
        }
        var indices: Set<Int> = []
        var walk = nearest
        while walk >= 0 {
            indices.insert(walk)
            walk -= beatsPerMeasure
        }
        walk = nearest + beatsPerMeasure
        while walk < beatTimes.count {
            indices.insert(walk)
            walk += beatsPerMeasure
        }
        return indices
    }

    /// Current 1-indexed position in the measure (e.g. 1..4 for WCS).
    /// `nil` when there's no anchor, no beats, or we haven't nearest-found
    /// a beat for `currentTime`.
    static func currentMeasurePosition(
        currentTime: Double,
        beatTimes: [Double],
        anchor: Double?,
        beatsPerMeasure: Int
    ) -> Int? {
        guard let anchor,
              beatsPerMeasure > 0,
              let currentIndex = nearestBeatIndex(to: currentTime, in: beatTimes),
              let anchorIndex = nearestBeatIndex(to: anchor, in: beatTimes) else {
            return nil
        }
        let rawOffset = currentIndex - anchorIndex
        let position = ((rawOffset % beatsPerMeasure) + beatsPerMeasure) % beatsPerMeasure
        return position + 1
    }

    /// Rescales an existing beat grid by factor. `factor = 2` doubles the
    /// grid resolution (inserts midpoints between adjacent beats); `factor
    /// = 0.5` halves it (keeps every other beat).
    static func rescale(beatTimes: [Double], factor: Double) -> [Double] {
        guard beatTimes.count >= 2, factor > 0 else { return beatTimes }
        if factor == 2 {
            var result: [Double] = []
            result.reserveCapacity(beatTimes.count * 2 - 1)
            for index in 0..<(beatTimes.count - 1) {
                result.append(beatTimes[index])
                result.append((beatTimes[index] + beatTimes[index + 1]) / 2)
            }
            result.append(beatTimes[beatTimes.count - 1])
            return result
        }
        if factor == 0.5 {
            return stride(from: 0, to: beatTimes.count, by: 2).map { beatTimes[$0] }
        }
        return beatTimes
    }
}
