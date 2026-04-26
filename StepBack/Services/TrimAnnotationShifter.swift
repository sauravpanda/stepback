import Foundation

/// Pure logic for "I just trimmed [trimStart, trimEnd] out of a clip — how
/// do I rebase the annotations?" Anything outside the new window is dropped;
/// anything that straddles an edge is clamped. Times are returned in the
/// new clip's timeline (i.e. with `trimStart` already subtracted).
enum TrimAnnotationShifter {

    struct ShiftedRange: Equatable {
        var start: Double
        var end: Double
    }

    /// Shifts a single time point. Returns nil if the point falls outside
    /// the kept range.
    static func shiftPoint(
        _ time: Double,
        trimStart: Double,
        trimEnd: Double
    ) -> Double? {
        guard time >= trimStart, time <= trimEnd else { return nil }
        return time - trimStart
    }

    /// Shifts a [start, end] range. Returns nil if the entire range falls
    /// outside the kept window or collapses to zero length after clamping.
    static func shiftRange(
        start: Double,
        end: Double,
        trimStart: Double,
        trimEnd: Double,
        minimumDuration: Double = 0.05
    ) -> ShiftedRange? {
        guard end > start else { return nil }
        guard end > trimStart, start < trimEnd else { return nil }
        let clampedStart = max(start, trimStart)
        let clampedEnd = min(end, trimEnd)
        guard clampedEnd - clampedStart >= minimumDuration else { return nil }
        return ShiftedRange(
            start: clampedStart - trimStart,
            end: clampedEnd - trimStart
        )
    }

    /// Drops beat times outside the kept window and rebases the rest.
    static func shiftBeatTimes(
        _ times: [Double],
        trimStart: Double,
        trimEnd: Double
    ) -> [Double] {
        times.compactMap { shiftPoint($0, trimStart: trimStart, trimEnd: trimEnd) }
    }
}
