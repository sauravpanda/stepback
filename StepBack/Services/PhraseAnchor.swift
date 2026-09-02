import Foundation

/// Coarse band energies per analysis frame, in decibels below the loudest
/// band in the clip.
///
/// This is the "what does it sound like right now" summary that phrase
/// detection compares across beats: nine bands from sub-bass to air, on a
/// dB scale so a hi-hat pattern arriving counts as much as a bass drop, and
/// floored so silence reads as very quiet rather than minus infinity.
struct BandSpectrogram: Equatable {
    let bandCount: Int
    let frameCount: Int
    /// Row-major: `frame * bandCount + band`. 0 at the loudest band-frame,
    /// `floorDecibels` at the quietest.
    let decibels: [Float]

    static let floorDecibels: Float = -60

    init(bandCount: Int, linear: [Float]) {
        self.bandCount = bandCount
        self.frameCount = bandCount > 0 ? linear.count / bandCount : 0
        let peak = linear.max() ?? 0
        guard peak > 0 else {
            decibels = [Float](repeating: 0, count: linear.count)
            return
        }
        let floor = peak * pow(10, Self.floorDecibels / 20)
        decibels = linear.map { 20 * log10(max($0, floor) / peak) }
    }

    subscript(frame: Int, band: Int) -> Float {
        decibels[frame * bandCount + band]
    }
}

/// Where the *phrase* starts, not just the bar.
///
/// `BeatDetector.estimateDownbeatPhase` decides which of four beats is "1"
/// from kick energy. That settles the bar and nothing else: the counter
/// reads in 8s and Phrase Catcher grades on 32s, and from a bar-level
/// anchor the 8-count's "1" is right half the time and the 32-count
/// boundary one time in eight. Kick energy cannot do better — it repeats
/// every bar.
///
/// What does change at a phrase boundary is the *texture*: a vocal comes
/// in, the drums drop out, the bass returns after a fill. So this measures
/// how much the sound changes at every beat — the distance between the
/// average spectrum of the eight beats before and the eight after, then
/// peak-picked so each change is credited to the one beat it lands on —
/// and votes for the offset whose candidate boundaries carry the most
/// change. The vote is hierarchical: bar, then 8-count, then 32. Each
/// level is a two- or four-way choice with plenty of evidence, where a
/// flat 32-way vote would spread the same evidence thin.
enum PhraseAnchor {

    /// The 8 the counter reads in.
    static let countLength = 8
    /// The 32 dancers phrase to.
    static let phraseLength = 32
    /// Beats either side of a boundary that the texture comparison averages
    /// over. One 8-count each way: long enough to smooth over a fill, short
    /// enough that neighbouring phrase changes stay separate.
    static let noveltyHalfWidth = 8

    /// One level of the vote.
    struct Vote: Equatable {
        /// Evidence for each candidate offset, in candidate order.
        let scores: [Double]

        /// The winning candidate. Ties go to the earliest — "leave the
        /// anchor where it is" when there is nothing to go on.
        var best: Int {
            scores.indices.max { scores[$0] < scores[$1] } ?? 0
        }

        /// 0 when the top candidates tie, 1 when the winner has all the
        /// evidence. Not stored anywhere yet; here for the day the UI
        /// wants to say "not sure about this one".
        var confidence: Double {
            let sorted = scores.sorted(by: >)
            guard let top = sorted.first, top > 0 else { return 0 }
            let runnerUp = sorted.count > 1 ? sorted[1] : 0
            return (top - runnerUp) / top
        }
    }

    // MARK: - Estimate

    /// Index into `beatTimes` of the beat to anchor the count on: the
    /// earliest beat that is a bar line, an 8-count start *and* a phrase
    /// start, as best the evidence can tell.
    ///
    /// `measureScores` is the kick-energy evidence per bar phase from
    /// `BeatDetector`; it is combined with texture change to choose the bar,
    /// because kick alone cannot separate the 1 from the 3 when the kick
    /// plays on both. Falls back to the coarser level whenever the clip is
    /// too short to vote at the finer one.
    static func estimate(
        beatTimes: [Double],
        measureScores: [Double],
        beatsPerMeasure: Int,
        spectrogram: BandSpectrogram,
        hopSeconds: Double,
        countLength: Int = countLength,
        phraseLength: Int = phraseLength
    ) -> Int? {
        guard beatsPerMeasure > 0,
              measureScores.count == beatsPerMeasure,
              beatTimes.count >= beatsPerMeasure else {
            return nil
        }
        let features = beatFeatures(spectrogram: spectrogram, beatTimes: beatTimes, hopSeconds: hopSeconds)
        let changes = peaks(in: novelty(features: features, halfWidth: noveltyHalfWidth))

        let measureVote = vote(peaks: changes, base: 0, step: 1, candidates: beatsPerMeasure, stride: beatsPerMeasure)
        let combined = zip(normalised(measureScores), normalised(measureVote.scores)).map(+)
        var anchor = combined.indices.max { combined[$0] < combined[$1] } ?? 0

        guard countLength % beatsPerMeasure == 0, beatTimes.count >= countLength else { return anchor }
        let eightVote = vote(
            peaks: changes,
            base: anchor,
            step: beatsPerMeasure,
            candidates: countLength / beatsPerMeasure,
            stride: countLength
        )
        anchor += eightVote.best * beatsPerMeasure

        guard phraseLength % countLength == 0, beatTimes.count >= phraseLength else { return anchor }
        let phraseVote = vote(
            peaks: changes,
            base: anchor,
            step: countLength,
            candidates: phraseLength / countLength,
            stride: phraseLength
        )
        return anchor + phraseVote.best * countLength
    }

    // MARK: - Features

    /// One spectral summary per beat: the mean band levels across the
    /// frames from that beat to the next. The final beat, having no next,
    /// takes the span of the one before it.
    static func beatFeatures(
        spectrogram: BandSpectrogram,
        beatTimes: [Double],
        hopSeconds: Double
    ) -> [[Float]] {
        let bands = spectrogram.bandCount
        let frames = spectrogram.frameCount
        guard bands > 0, frames > 0, hopSeconds > 0, !beatTimes.isEmpty else { return [] }
        let starts = beatTimes.map { Int(($0 / hopSeconds).rounded()) }
        let typicalSpan = starts.count >= 2 ? max(1, starts[starts.count - 1] - starts[starts.count - 2]) : 1

        return starts.indices.map { index in
            let start = starts[index]
            let end = index + 1 < starts.count ? starts[index + 1] : start + typicalSpan
            let lower = min(max(0, start), frames - 1)
            let upper = min(max(lower + 1, end), frames)
            var sums = [Float](repeating: 0, count: bands)
            for frame in lower..<upper {
                for band in 0..<bands {
                    sums[band] += spectrogram[frame, band]
                }
            }
            let count = Float(upper - lower)
            return sums.map { $0 / count }
        }
    }

    /// How much the sound changes at each beat: the distance between the
    /// mean feature of the `halfWidth` beats before it and the `halfWidth`
    /// beats from it onwards. Zero where there isn't a full window on both
    /// sides.
    static func novelty(features: [[Float]], halfWidth: Int) -> [Double] {
        let count = features.count
        var result = [Double](repeating: 0, count: count)
        guard halfWidth > 0, count >= 2 * halfWidth + 1, let bands = features.first?.count, bands > 0 else {
            return result
        }
        // Prefix sums make each block mean O(bands) rather than O(width).
        var prefix = [[Double]](repeating: [Double](repeating: 0, count: bands), count: count + 1)
        for index in 0..<count {
            for band in 0..<bands {
                prefix[index + 1][band] = prefix[index][band] + Double(features[index][band])
            }
        }
        let width = Double(halfWidth)
        for index in halfWidth...(count - halfWidth) {
            var distance = 0.0
            for band in 0..<bands {
                let before = (prefix[index][band] - prefix[index - halfWidth][band]) / width
                let after = (prefix[index + halfWidth][band] - prefix[index][band]) / width
                distance += (after - before) * (after - before)
            }
            result[index] = distance.squareRoot()
        }
        return result
    }

    /// Keeps only the local maxima of a novelty curve, zeroing the rest.
    ///
    /// Block averaging smears every change into a ramp sixteen beats wide,
    /// and the sum of a ramp is the same no matter which beat of the bar
    /// you sample it on — so a vote on the raw curve learns nothing. The
    /// peak is where the change actually happened, and the vote wants only
    /// that. The first and last valid beats are excluded: with a zero
    /// neighbour on one side they'd read as peaks whatever the music did.
    static func peaks(in novelty: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: novelty.count)
        guard novelty.count >= 3 else { return result }
        for index in 1..<(novelty.count - 1) where novelty[index] > 0 {
            let value = novelty[index]
            let left = novelty[index - 1]
            let right = novelty[index + 1]
            guard left > 0, right > 0, value > left, value >= right else { continue }
            result[index] = value
        }
        return result
    }

    // MARK: - Voting

    /// Sums the peaks that fall on each candidate's comb of beats. Candidate
    /// `c` claims beats `base + c * step` and every `stride`-th beat after.
    static func vote(peaks: [Double], base: Int, step: Int, candidates: Int, stride: Int) -> Vote {
        guard candidates > 0, stride > 0 else { return Vote(scores: []) }
        var scores = [Double](repeating: 0, count: candidates)
        for candidate in 0..<candidates {
            var index = ((base + candidate * step) % stride + stride) % stride
            while index < peaks.count {
                scores[candidate] += peaks[index]
                index += stride
            }
        }
        return Vote(scores: scores)
    }

    /// Scales scores to sum to one so two kinds of evidence can be added.
    /// All-zero stays all-zero: no evidence contributes nothing.
    static func normalised(_ scores: [Double]) -> [Double] {
        let total = scores.reduce(0, +)
        guard total > 0 else { return scores }
        return scores.map { $0 / total }
    }
}
