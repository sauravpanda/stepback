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

/// What one tap earned, the moment it landed.
///
/// Scoring at the end of a take tells you how you did; this tells you how
/// you're *doing*, which is what actually trains timing — feedback a second
/// late is feedback about a different beat.
struct TapFeedback: Equatable {
    /// Signed milliseconds to the nearest target. Negative = early.
    let offsetMs: Double
    /// Whether the tap fell inside the catch window of that target.
    let isHit: Bool

    var rating: StepRating {
        StepRating(offsetMs: offsetMs)
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

    /// Grades a single tap against the nearest of `targets`, for feedback
    /// in the moment. Nil when there is nothing to grade against.
    ///
    /// Deliberately independent of which taps have already claimed which
    /// targets: the dancer wants to know how *this* tap landed, and the
    /// double-tap bookkeeping belongs to the end-of-take `score`.
    static func feedback(
        forTap time: Double,
        targets: [Double],
        toleranceSeconds: Double
    ) -> TapFeedback? {
        guard let index = BeatGrid.nearestBeatIndex(to: time, in: targets) else { return nil }
        let offset = time - targets[index]
        return TapFeedback(
            offsetMs: offset * 1_000,
            isHit: abs(offset) <= toleranceSeconds + floatSlop
        )
    }

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

// MARK: - Navigation

/// Transport helpers for moving around a track in musical units rather
/// than seconds. Separated into an extension to keep the enum body inside
/// SwiftLint's `type_body_length` limit.
extension PhraseGrid {

    /// How far into a phrase you can be and still have "previous" mean
    /// *restart this one*, matching the way a music player's back button
    /// behaves within a track.
    static let rewindGraceSeconds: Double = 1.0

    /// The next phrase start strictly after `time`, or nil at the last one.
    static func phraseStart(
        after time: Double,
        beatTimes: [Double],
        anchor: Double?,
        phraseLength: Int
    ) -> Double? {
        phraseStartTimes(beatTimes: beatTimes, anchor: anchor, phraseLength: phraseLength)
            .first { $0 > time }
    }

    /// Where a "previous phrase" press should land.
    ///
    /// Within `rewindGraceSeconds` of the current phrase start it steps back
    /// to the previous phrase; past that it returns to the top of the
    /// current one.
    static func phraseStart(
        before time: Double,
        beatTimes: [Double],
        anchor: Double?,
        phraseLength: Int
    ) -> Double? {
        let starts = phraseStartTimes(
            beatTimes: beatTimes,
            anchor: anchor,
            phraseLength: phraseLength
        )
        let threshold = time - rewindGraceSeconds
        if let restart = starts.last(where: { $0 <= threshold }) {
            return restart
        }
        return starts.last { $0 < time } ?? starts.first
    }

    /// Start and end of the phrase containing `time`, for looping it.
    ///
    /// The end is the next phrase start, so consecutive loops butt up
    /// against each other with no gap or overlap. Falls back to the final
    /// beat when `time` sits in the last phrase.
    static func currentPhraseBounds(
        at time: Double,
        beatTimes: [Double],
        anchor: Double?,
        phraseLength: Int
    ) -> (start: Double, end: Double)? {
        let starts = phraseStartTimes(
            beatTimes: beatTimes,
            anchor: anchor,
            phraseLength: phraseLength
        )
        guard let start = starts.last(where: { $0 <= time }) ?? starts.first else { return nil }
        let end = starts.first { $0 > start } ?? beatTimes.last
        guard let end, end > start else { return nil }
        return (start, end)
    }

    /// Moves an anchor `byBeats` along the grid, for nudging a guessed
    /// downbeat onto the real one.
    ///
    /// Only the anchor's position *within* the phrase matters — every count
    /// is derived by walking `period` beats either way from it — so a nudge
    /// that would run off the end of the grid wraps back a whole `period`
    /// instead. Clamping there would silently change which beat is "1".
    /// With the default period of one beat the wrap is a plain clamp, so
    /// holding the button down still can't walk the anchor off either end.
    static func shiftAnchor(
        _ anchor: Double,
        byBeats: Int,
        in beatTimes: [Double],
        keepingPhaseOf period: Int = 1
    ) -> Double? {
        guard !beatTimes.isEmpty,
              let index = BeatGrid.nearestBeatIndex(to: anchor, in: beatTimes) else {
            return nil
        }
        var shifted = index + byBeats
        if period > 1 {
            if shifted >= beatTimes.count { shifted -= period }
            if shifted < 0 { shifted += period }
        }
        return beatTimes[min(max(0, shifted), beatTimes.count - 1)]
    }
}
