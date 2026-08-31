import Foundation

/// How a set of phrase taps scored against the true phrase starts.
///
/// Three outcomes rather than two: a tap that lands nowhere near a phrase
/// (`falsePositives`) is a different mistake from failing to tap a phrase
/// at all (`misses`), and a drill that only counted hits would let someone
/// score well by mashing the pad.
struct PhraseScore: Equatable {
    var hits: Int = 0
    var misses: Int = 0
    var falsePositives: Int = 0
    /// Signed millisecond offsets of the hits. Negative = early.
    var offsetsMs: [Double] = []

    var attempted: Int {
        hits + misses + falsePositives
    }

    /// Hits over everything that could have gone wrong. Zero when nothing
    /// was attempted, so an untouched drill reads as 0%, not 100%.
    var accuracy: Double {
        guard attempted > 0 else { return 0 }
        return Double(hits) / Double(attempted)
    }

    /// Mean signed offset of the hits. Negative = consistently early,
    /// positive = consistently late — the number worth practising against.
    var averageOffsetMs: Double? {
        guard !offsetsMs.isEmpty else { return nil }
        return offsetsMs.reduce(0, +) / Double(offsetsMs.count)
    }
}

/// Pure helpers for reasoning about musical phrases — the 8- and 32-count
/// groupings dancers actually hear.
///
/// Nothing here *detects* structure. Phrases in social dance music are
/// strictly periodic, so once `BeatDetector` has produced a beat grid and
/// the user has anchored beat 1, every phrase boundary is arithmetic. That
/// makes the ground truth exact and free.
///
/// Value-in / value-out like `BeatGrid`, so drills stay testable without an
/// AVPlayer.
enum PhraseGrid {

    /// Default catch window, as a fraction of one beat. Generous enough
    /// that hearing the phrase counts even when the tap is loose.
    static let defaultToleranceFraction: Double = 0.4

    /// Slop on the window comparison. Beat times arrive from repeated
    /// division and multiplication, so a tap that is arithmetically exactly
    /// at the tolerance can land an ulp outside it — `abs(2.2 - 2.0)` is
    /// `0.2000000000000002`. Widening by a nanosecond keeps the boundary
    /// meaning what it says without loosening the drill in any way a
    /// dancer could perceive.
    private static let floatSlop: Double = 1e-9

    // MARK: - Phrase boundaries

    /// Absolute times of every phrase start. `phraseLength` counts beats —
    /// 8 for an 8-count, 32 for a full phrase.
    ///
    /// The modulus walk is `BeatGrid.downbeatIndices`, which already
    /// computes "every Nth beat either side of an anchor". A phrase grid is
    /// that same walk with a longer stride, so it delegates rather than
    /// reimplementing.
    static func phraseStartTimes(
        beatTimes: [Double],
        anchor: Double?,
        phraseLength: Int
    ) -> [Double] {
        BeatGrid.downbeatIndices(
            beatTimes: beatTimes,
            anchor: anchor,
            beatsPerMeasure: phraseLength
        )
        .sorted()
        .map { beatTimes[$0] }
    }

    /// Phrase starts limited to `range`. Drills must score only the window
    /// actually played — otherwise every phrase before the user pressed
    /// start is counted against them as a miss.
    static func phraseStartTimes(
        beatTimes: [Double],
        anchor: Double?,
        phraseLength: Int,
        in range: ClosedRange<Double>
    ) -> [Double] {
        phraseStartTimes(
            beatTimes: beatTimes,
            anchor: anchor,
            phraseLength: phraseLength
        )
        .filter { range.contains($0) }
    }

    /// 1-indexed position within the phrase (1...phraseLength), for the
    /// live counter. Delegates to `BeatGrid`; exists so drills only ever
    /// talk to `PhraseGrid`.
    static func phrasePosition(
        currentTime: Double,
        beatTimes: [Double],
        anchor: Double?,
        phraseLength: Int
    ) -> Int? {
        BeatGrid.currentMeasurePosition(
            currentTime: currentTime,
            beatTimes: beatTimes,
            anchor: anchor,
            beatsPerMeasure: phraseLength
        )
    }

    // MARK: - Tolerance

    /// Catch window in seconds, scaled to the tempo. A fixed millisecond
    /// window would be unfairly tight at 75 BPM and unfairly loose at 160,
    /// because what a dancer perceives as "on the phrase" scales with the
    /// length of a beat.
    static func toleranceSeconds(
        bpm: Double,
        fractionOfBeat: Double = defaultToleranceFraction
    ) -> Double {
        guard bpm > 0, fractionOfBeat > 0 else { return 0 }
        return 60.0 / bpm * fractionOfBeat
    }

    // MARK: - Scoring

    /// Grades `taps` against `phraseStarts`.
    ///
    /// Walks the phrase starts in order; each claims its nearest unclaimed
    /// tap inside the window. Matching from the starts rather than the taps
    /// keeps the result stable when someone double-taps a phrase — the
    /// second tap becomes a false positive instead of stealing the next
    /// phrase's credit. The window is inclusive at exactly `tolerance`.
    static func score(
        taps: [Double],
        phraseStarts: [Double],
        toleranceSeconds: Double
    ) -> PhraseScore {
        guard toleranceSeconds > 0 else {
            return PhraseScore(
                hits: 0,
                misses: phraseStarts.count,
                falsePositives: taps.count,
                offsetsMs: []
            )
        }

        var claimed = [Bool](repeating: false, count: taps.count)
        var score = PhraseScore()

        for start in phraseStarts {
            var bestIndex: Int?
            var bestDistance = toleranceSeconds + floatSlop
            for (index, tap) in taps.enumerated() where !claimed[index] {
                let distance = abs(tap - start)
                if distance <= bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            if let bestIndex {
                claimed[bestIndex] = true
                score.hits += 1
                score.offsetsMs.append((taps[bestIndex] - start) * 1_000)
            } else {
                score.misses += 1
            }
        }

        score.falsePositives = claimed.filter { !$0 }.count
        return score
    }
}
