import Foundation

/// Dynamic-programming beat tracker, after Ellis, *Beat Tracking by
/// Dynamic Programming* (2007).
///
/// `BeatDetector` used to lay a rigid lattice over the clip: one tempo, one
/// phase, every beat an exact multiple of the analysis hop. That is right
/// for a produced track and wrong for everything else — a live band, a
/// class recording with a count-in, a DJ blend — and even on produced
/// tracks the lattice's tempo was quantised to whole hops, so a 2% error
/// put the count a full beat off half a minute from wherever it locked.
///
/// The tracker instead chooses, for every frame, the best chain of
/// preceding beats: each beat earns the onset energy under it and pays a
/// penalty for straying from the expected spacing. The result follows the
/// music where it moves and coasts at the expected tempo where it goes
/// quiet. When the tracked beats turn out to fit a constant tempo after
/// all, `fitLattice` says so and the caller can snap to that instead —
/// a produced track deserves a grid with no jitter at all.
enum BeatTracker {

    /// How hard the tracker resists tempo changes. The penalty per beat is
    /// `tightness * ln(interval / period)^2` against onset energy that has
    /// been normalised to unit standard deviation. 100 is librosa's
    /// default: a 5% stretch costs about 0.25, a skipped or doubled beat
    /// about 48 — so drift is followed and octave jumps are not.
    static let defaultTightness: Double = 100

    /// Onsets below this fraction of the loudest one don't start the beat
    /// chain, so leading silence isn't filled with beats nobody can hear.
    static let firstBeatFraction: Double = 0.01

    // MARK: - Tracking

    /// Frame indices of the tracked beats, in order.
    ///
    /// `period` is the expected beat spacing in frames; fractional is fine.
    /// Empty when the envelope is silent or shorter than a beat.
    static func track(
        onsets: [Float],
        period: Double,
        tightness: Double = defaultTightness
    ) -> [Int] {
        guard period >= 1, tightness > 0, onsets.count > Int(period) else { return [] }
        let local = localScore(onsets: onsets, period: period)
        guard let peak = local.max(), peak > 0 else { return [] }

        // A predecessor sits between half a beat and two beats back.
        // Closer is a double hit; further is a dropped beat.
        let nearest = max(1, Int((period / 2).rounded()))
        let furthest = max(nearest + 1, Int((period * 2).rounded()))
        let gaps = Array(nearest...furthest)
        let penalties = gaps.map { gap -> Double in
            let ratio = log(Double(gap) / period)
            return -tightness * ratio * ratio
        }

        var cumulative = [Double](repeating: 0, count: local.count)
        var backlink = [Int](repeating: -1, count: local.count)
        let firstBeatFloor = firstBeatFraction * peak
        var chainStarted = false

        for frame in 0..<local.count {
            var best = -Double.infinity
            var bestFrom = -1
            for (slot, gap) in gaps.enumerated() {
                let from = frame - gap
                if from >= 0 {
                    let candidate = penalties[slot] + cumulative[from]
                    if candidate > best {
                        best = candidate
                        bestFrom = from
                    }
                } else if penalties[slot] > best {
                    // Reaching back before the clip began: the chain may
                    // simply start here, at the cost of the spacing
                    // penalty alone.
                    best = penalties[slot]
                    bestFrom = -1
                }
            }
            cumulative[frame] = local[frame] + best
            // Frames before the first audible onset get no predecessor, so
            // backtracking stops at the first real beat rather than
            // marching on through silence.
            if chainStarted || local[frame] >= firstBeatFloor {
                backlink[frame] = bestFrom
                chainStarted = true
            }
        }

        guard let last = lastBeat(cumulative: cumulative) else { return [] }
        var beats = [last]
        var cursor = backlink[last]
        while cursor >= 0 {
            beats.append(cursor)
            cursor = backlink[cursor]
        }
        beats.reverse()
        return trimmed(beats: beats, local: local)
    }

    /// Drops beats at either end that sit on nothing.
    ///
    /// The chain coasts at the expected tempo through silence, which is
    /// what you want mid-clip and not what you want past the last onset or
    /// before the first: those beats belong to the tempo prior, not the
    /// music, and would tilt the constant-tempo fit. Each beat's local score
    /// is smoothed over its neighbours and the ends trimmed back to the
    /// first and last that clear half the RMS — the original's recipe.
    static func trimmed(beats: [Int], local: [Double]) -> [Int] {
        guard beats.count >= 3 else { return beats }
        let scores = beats.map { local[$0] }
        // Five-point Hann: 0, ½, 1, ½, 0.
        let weights = (0..<5).map { 0.5 * (1 - cos(2 * Double.pi * Double($0) / 4)) }
        let smoothed = scores.indices.map { index -> Double in
            var sum = 0.0
            for (offset, weight) in zip(-2...2, weights) {
                let source = index + offset
                guard source >= 0, source < scores.count else { continue }
                sum += weight * scores[source]
            }
            return sum
        }
        let rms = (smoothed.reduce(0) { $0 + $1 * $1 } / Double(smoothed.count)).squareRoot()
        let threshold = 0.5 * rms
        guard let first = smoothed.firstIndex(where: { $0 > threshold }),
              let last = smoothed.lastIndex(where: { $0 > threshold }),
              last >= first else {
            return beats
        }
        return Array(beats[first...last])
    }

    /// Onset energy normalised to unit variance and lightly smoothed, so a
    /// beat landing a frame either side of an onset peak still earns most
    /// of it. Gaussian of width `period / 32`, as in the original.
    static func localScore(onsets: [Float], period: Double) -> [Double] {
        guard !onsets.isEmpty else { return [] }
        let values = onsets.map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let deviation = variance.squareRoot()
        guard deviation > 0 else { return [Double](repeating: 0, count: values.count) }

        let sigma = max(0.5, period / 32)
        let radius = Int((3 * sigma).rounded(.up))
        let kernel = (-radius...radius).map { exp(-0.5 * pow(Double($0) / sigma, 2)) }
        var smoothed = [Double](repeating: 0, count: values.count)
        for index in values.indices {
            var sum = 0.0
            for (offset, weight) in zip(-radius...radius, kernel) {
                let source = index + offset
                guard source >= 0, source < values.count else { continue }
                sum += weight * values[source]
            }
            smoothed[index] = sum / deviation
        }
        return smoothed
    }

    /// The frame the chain ends on: the last local maximum of the
    /// cumulative score that is at least half the typical one. The score
    /// only ever grows, so this is the final real beat — a stray onset in
    /// the tail can't drag the chain past the music.
    private static func lastBeat(cumulative: [Double]) -> Int? {
        let count = cumulative.count
        guard count > 1 else { return count == 1 ? 0 : nil }
        var maxima: [Int] = []
        for index in 1..<count {
            let right = index + 1 < count ? cumulative[index + 1] : cumulative[index]
            if cumulative[index] > cumulative[index - 1], cumulative[index] >= right {
                maxima.append(index)
            }
        }
        guard !maxima.isEmpty else { return count - 1 }
        let sorted = maxima.map { cumulative[$0] }.sorted()
        let median = sorted[sorted.count / 2]
        return maxima.last { cumulative[$0] * 2 > median } ?? maxima.last
    }

    // MARK: - Sub-frame refinement

    /// Moves each tracked frame onto the vertex of the onset peak under it.
    ///
    /// The tracker works in whole frames; the true onset is somewhere
    /// inside one. Fitting a parabola through the peak and its neighbours
    /// recovers where, to a fraction of a frame. A beat sitting on a flat
    /// or in silence has no peak to refine against and is left alone.
    static func refine(frames: [Int], onsets: [Float]) -> [Double] {
        frames.map { frame in
            guard frame >= 0, frame < onsets.count else { return Double(frame) }
            // The smoothing in `localScore` can park a beat one frame off
            // the raw peak, so look one frame either side first. Strictly
            // greater, so a flat neighbourhood keeps the tracker's frame.
            var peak = frame
            for candidate in [frame - 1, frame + 1] where candidate >= 0 && candidate < onsets.count {
                if onsets[candidate] > onsets[peak] {
                    peak = candidate
                }
            }
            guard peak > 0, peak + 1 < onsets.count else { return Double(peak) }
            let left = Double(onsets[peak - 1])
            let centre = Double(onsets[peak])
            let right = Double(onsets[peak + 1])
            let curvature = left - 2 * centre + right
            guard centre >= left, centre >= right, curvature < 0 else { return Double(peak) }
            let shift = 0.5 * (left - right) / curvature
            return Double(peak) + min(0.5, max(-0.5, shift))
        }
    }

    // MARK: - Constant-tempo fit

    /// A constant-tempo grid: beat `i` falls at `firstBeat + i * period`.
    struct Lattice: Equatable {
        let firstBeat: Double
        let period: Double

        /// Every grid point inside `range`, in order.
        func times(covering range: ClosedRange<Double>) -> [Double] {
            guard period > 0 else { return [] }
            let first = Int(((range.lowerBound - firstBeat) / period).rounded(.up))
            let last = Int(((range.upperBound - firstBeat) / period).rounded(.down))
            guard last >= first else { return [] }
            return (first...last).map { firstBeat + Double($0) * period }
        }
    }

    /// A beat further than this from the fitted grid is an outlier — the
    /// tracker coasting through a break at a slightly wrong tempo, say —
    /// and is left out of the fit rather than allowed to bend it.
    static let latticeOutlierSeconds: Double = 0.035
    /// At least this share of beats must sit on the grid for it to count as
    /// explaining the take.
    static let latticeMinimumInlierFraction: Double = 0.8
    /// And those that do must sit tight. About one analysis frame.
    static let latticeMaximumInlierRMS: Double = 0.015

    /// Fits a constant-tempo grid to tracked beats, or nil when no such
    /// grid explains them — the tempo moved and the tracked beats should
    /// be kept as they are.
    ///
    /// Least squares of time against beat index, in two passes: the first
    /// finds the grid, the second refits on the beats that agree with it,
    /// so a stretch where the tracker coasted through silence doesn't tilt
    /// the tempo for the whole clip.
    static func fitLattice(beatTimes: [Double]) -> Lattice? {
        guard beatTimes.count >= 8 else { return nil }
        let indices = Array(beatTimes.indices)
        guard let rough = regress(beatTimes, at: indices) else { return nil }
        let inliers = indices.filter { index in
            abs(beatTimes[index] - (rough.firstBeat + Double(index) * rough.period)) <= latticeOutlierSeconds
        }
        guard Double(inliers.count) >= latticeMinimumInlierFraction * Double(beatTimes.count),
              let lattice = regress(beatTimes, at: inliers) else {
            return nil
        }
        let squares = inliers.reduce(0.0) { sum, index in
            let residual = beatTimes[index] - (lattice.firstBeat + Double(index) * lattice.period)
            return sum + residual * residual
        }
        guard (squares / Double(inliers.count)).squareRoot() <= latticeMaximumInlierRMS else {
            return nil
        }
        return lattice
    }

    private static func regress(_ times: [Double], at indices: [Int]) -> Lattice? {
        guard indices.count >= 2 else { return nil }
        let count = Double(indices.count)
        let meanIndex = indices.reduce(0.0) { $0 + Double($1) } / count
        let meanTime = indices.reduce(0.0) { $0 + times[$1] } / count
        var covariance = 0.0
        var variance = 0.0
        for index in indices {
            let dx = Double(index) - meanIndex
            covariance += dx * (times[index] - meanTime)
            variance += dx * dx
        }
        guard variance > 0 else { return nil }
        let period = covariance / variance
        guard period > 0 else { return nil }
        return Lattice(firstBeat: meanTime - period * meanIndex, period: period)
    }

    // MARK: - Extension

    /// Continues a beat sequence to both ends of `range` at the tempo it
    /// arrives with, so the count keeps going through an intro or an outro
    /// the tracker had nothing to lock onto.
    static func extended(beatTimes: [Double], toCover range: ClosedRange<Double>) -> [Double] {
        guard beatTimes.count >= 2 else { return beatTimes }
        var result = beatTimes
        let lead = medianInterval(Array(beatTimes.prefix(5)))
        let tail = medianInterval(Array(beatTimes.suffix(5)))
        guard lead > 0, tail > 0 else { return result }
        var head = result[0] - lead
        while head >= range.lowerBound {
            result.insert(head, at: 0)
            head -= lead
        }
        var next = result[result.count - 1] + tail
        while next <= range.upperBound {
            result.append(next)
            next += tail
        }
        return result
    }

    /// Median spacing between consecutive beats; 0 for fewer than two.
    static func medianInterval(_ beatTimes: [Double]) -> Double {
        guard beatTimes.count >= 2 else { return 0 }
        let intervals = zip(beatTimes.dropFirst(), beatTimes).map { $0 - $1 }.sorted()
        return intervals[intervals.count / 2]
    }
}
