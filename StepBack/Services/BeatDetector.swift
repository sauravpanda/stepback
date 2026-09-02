import Accelerate
import AVFoundation
import Foundation

struct BeatAnalysis: Equatable {
    let bpm: Double
    let beatTimes: [Double]
    /// Best guess at a beat to count from: a bar line that is also the top
    /// of an 8 and the start of a 32-count phrase, judged from kick energy
    /// and from where the texture of the music changes. Nil when there
    /// aren't enough beats to judge. A guess, not gospel — the UI always
    /// leaves the user a way to nudge it.
    let downbeatSeconds: Double?

    init(bpm: Double, beatTimes: [Double], downbeatSeconds: Double? = nil) {
        self.bpm = bpm
        self.beatTimes = beatTimes
        self.downbeatSeconds = downbeatSeconds
    }
}

enum BeatDetectorError: Error, Equatable {
    case noAudioTrack
    case audioExtractionFailed
}

/// On-device beat detector. Apple SDKs only (AVFoundation + Accelerate).
///
/// Pipeline: audio extraction → one STFT pass yielding a broadband onset
/// envelope, a kick-band onset envelope and a coarse band spectrogram
/// (`BeatDetector+Spectral`) → tempo via autocorrelation of the onset
/// envelope → beat tracking by dynamic programming (`BeatTracker`),
/// snapped to a constant-tempo grid when one fits → bar from kick energy,
/// 8-count and phrase from texture change (`PhraseAnchor`).
///
/// The anchor is a *guess*, offered so the Listen tab can start counting
/// without making the user place beat 1 by hand. It is wrong often enough
/// that every surface using it must keep a correction one tap away.
enum BeatDetector {

    // MARK: - Tunables

    static let sampleRate: Double = 22_050
    static let windowSize: Int = 1_024
    /// Quarter-window hop: 11.6ms frames. The tracker places beats to the
    /// frame and then refines within it, so the hop bounds how tight a grid
    /// can get; half this again would double analysis time for a gain no
    /// dancer could feel.
    static let hopSize: Int = 256
    static let minBPM: Double = 60
    static let maxBPM: Double = 200
    static let foldLowerBound: Double = 75
    static let foldUpperBound: Double = 160

    /// FFT bins used to judge *which* beat is beat 1.
    ///
    /// At 22.05 kHz with a 1024-point window each bin spans ~21.5 Hz, so
    /// `1..<8` covers roughly 21–172 Hz: the kick drum. Deliberately not
    /// the broadband envelope — spectral flux peaks on the snare at least
    /// as hard as the kick, and in most dance music the snare is on 2 and
    /// 4, so a broadband guess would reliably anchor the count on the
    /// backbeat. Bin 0 is DC and is skipped.
    static let kickBins: Range<Int> = 1..<8

    /// Band edges, in Hz, of the coarse spectrogram phrase detection reads.
    /// Roughly an octave each from the kick up: enough to tell a bass drop
    /// from a vocal entry from a hi-hat pattern, few enough to stay cheap.
    static let structureBandEdgesHz: [Double] = [20, 60, 120, 250, 500, 1_000, 2_000, 4_000, 8_000, 11_025]

    /// How far the onset a frame reports actually sits *after* the frame's
    /// start. Spectral flux peaks while the attack is in the back half of
    /// the window — about three quarters of the way in for a sharp
    /// transient, nearer the middle for a soft one — so a frame's start
    /// time runs 400–600 samples ahead of the beat. Half a window splits
    /// the difference. Without this the whole grid sat ~25ms early.
    static let onsetLatencySeconds: Double = Double(windowSize / 2) / sampleRate

    /// Default metre. Matches `DanceClip.beatsPerMeasure`.
    static let defaultBeatsPerMeasure: Int = 4

    // MARK: - Public API

    static func analyze(asset: AVAsset) async throws -> BeatAnalysis {
        let samples = try await extractMonoFloatSamples(from: asset)
        return analyzeSamples(samples, sampleRate: sampleRate)
    }

    /// Pure entry point: feed a float-mono PCM buffer, get back BPM + beats.
    /// Exposed for tests and for future live-analysis experiments.
    static func analyzeSamples(
        _ samples: [Float],
        sampleRate: Double,
        beatsPerMeasure: Int = defaultBeatsPerMeasure
    ) -> BeatAnalysis {
        guard samples.count >= windowSize else {
            return BeatAnalysis(bpm: 0, beatTimes: [])
        }
        let features = computeSpectralFeatures(
            samples: samples,
            windowSize: windowSize,
            hopSize: hopSize,
            lowBandBins: kickBins,
            bandBins: structureBandBins(sampleRate: sampleRate, windowSize: windowSize)
        )
        let hopSeconds = Double(hopSize) / sampleRate
        let coarseBPM = estimateTempo(onsets: features.full, hopSeconds: hopSeconds)
        let tracked = trackBeats(onsets: features.full, bpm: coarseBPM, hopSeconds: hopSeconds)
        let anchor = estimateAnchor(
            features: features,
            beatTimes: tracked.beatTimes,
            hopSeconds: hopSeconds,
            beatsPerMeasure: beatsPerMeasure
        )
        return BeatAnalysis(
            bpm: tracked.bpm,
            beatTimes: tracked.beatTimes,
            downbeatSeconds: anchor.flatMap { tracked.beatTimes.indices.contains($0) ? tracked.beatTimes[$0] : nil }
        )
    }

    // MARK: - Audio extraction

    private static func extractMonoFloatSamples(from asset: AVAsset) async throws -> [Float] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw BeatDetectorError.noAudioTrack }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? BeatDetectorError.audioExtractionFailed
        }

        var samples: [Float] = []
        samples.reserveCapacity(1 << 20)

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            if status != noErr { continue }
            guard let ptr = dataPointer else { continue }
            let count = length / MemoryLayout<Float>.size
            if count == 0 { continue }
            ptr.withMemoryRebound(to: Float.self, capacity: count) { floatPtr in
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: count))
            }
        }

        if reader.status == .failed {
            throw reader.error ?? BeatDetectorError.audioExtractionFailed
        }
        return samples
    }
}

// MARK: - Tempo

/// Split into extensions to keep each body under SwiftLint's
/// `type_body_length` limit; these are ordinary members of `BeatDetector`.
extension BeatDetector {

    /// Tempo in BPM from the autocorrelation of the onset envelope.
    ///
    /// The envelope is mean-centred first so the correlation measures
    /// rhythm rather than loudness, and each lag is normalised by its
    /// overlap so shorter lags don't win merely for having more terms. The
    /// peak lag is then refined by fitting a parabola through it and its
    /// neighbours: whole-frame lags can only express tempos ~2–5% apart at
    /// dance speeds, and a grid laid at the wrong one of those drifts a
    /// full beat in under a minute.
    static func estimateTempo(onsets: [Float], hopSeconds: Double) -> Double {
        guard !onsets.isEmpty, hopSeconds > 0 else { return 0 }

        let minLag = max(1, Int((60.0 / maxBPM / hopSeconds).rounded()))
        let maxLag = Int((60.0 / minBPM / hopSeconds).rounded())
        let clampedMaxLag = min(maxLag, onsets.count - 1)
        guard clampedMaxLag > minLag else { return 120 }

        let count = vDSP_Length(onsets.count)
        var mean: Float = 0
        vDSP_meanv(onsets, 1, &mean, count)
        var negativeMean = -mean
        var centred = [Float](repeating: 0, count: onsets.count)
        vDSP_vsadd(onsets, 1, &negativeMean, &centred, 1, count)

        var scores = [Float](repeating: -.infinity, count: clampedMaxLag + 1)
        centred.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for lag in minLag...clampedMaxLag {
                var score: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &score, vDSP_Length(onsets.count - lag))
                scores[lag] = score / Float(onsets.count - lag)
            }
        }
        let bestLag = (minLag...clampedMaxLag).max { scores[$0] < scores[$1] } ?? minLag

        var lag = Double(bestLag)
        if bestLag > minLag, bestLag < clampedMaxLag {
            let left = Double(scores[bestLag - 1])
            let centre = Double(scores[bestLag])
            let right = Double(scores[bestLag + 1])
            let curvature = left - 2 * centre + right
            if curvature < 0 {
                lag += min(0.5, max(-0.5, 0.5 * (left - right) / curvature))
            }
        }

        var bpm = 60.0 / (lag * hopSeconds)
        while bpm > foldUpperBound { bpm /= 2 }
        while bpm < foldLowerBound, bpm > 0 { bpm *= 2 }
        return bpm
    }
}

// MARK: - Beat tracking

extension BeatDetector {

    /// Absolute beat times for the envelope. Kept for callers that only
    /// want the grid; `trackBeats` also reports the tempo it settled on.
    static func alignBeats(onsets: [Float], bpm: Double, hopSeconds: Double) -> [Double] {
        trackBeats(onsets: onsets, bpm: bpm, hopSeconds: hopSeconds).beatTimes
    }

    /// Beat times across the whole envelope, plus the tempo they imply.
    ///
    /// `BeatTracker` follows the music; if what it followed turns out to be
    /// a constant tempo, the beats are snapped to that grid — exact
    /// spacing, no frame jitter, and a BPM read off hundreds of beats
    /// rather than one autocorrelation peak. Otherwise the tracked beats
    /// stand and are extended at their local tempo to cover intro and
    /// outro. A clip with nothing to track falls back to a rigid grid at
    /// the estimated tempo, which is what the old detector always did.
    static func trackBeats(
        onsets: [Float],
        bpm: Double,
        hopSeconds: Double
    ) -> (beatTimes: [Double], bpm: Double) {
        guard bpm > 0, hopSeconds > 0, !onsets.isEmpty else { return ([], bpm) }
        let span = 0...(Double(onsets.count) * hopSeconds)
        let frames = BeatTracker.track(onsets: onsets, period: 60.0 / bpm / hopSeconds)
        guard frames.count >= 2 else {
            return (rigidLattice(onsets: onsets, bpm: bpm, hopSeconds: hopSeconds), bpm)
        }
        let times = BeatTracker.refine(frames: frames, onsets: onsets)
            .map { $0 * hopSeconds + onsetLatencySeconds }
        if let lattice = BeatTracker.fitLattice(beatTimes: times) {
            return (lattice.times(covering: span), 60.0 / lattice.period)
        }
        let interval = BeatTracker.medianInterval(times)
        return (
            BeatTracker.extended(beatTimes: times, toCover: span),
            interval > 0 ? 60.0 / interval : bpm
        )
    }

    /// A fixed grid at `bpm`, phased to put the most onset energy under
    /// the beats. The pre-tracker algorithm, kept as the fallback for an
    /// envelope too quiet or too short to track.
    static func rigidLattice(onsets: [Float], bpm: Double, hopSeconds: Double) -> [Double] {
        guard bpm > 0, hopSeconds > 0, !onsets.isEmpty else { return [] }
        let hopsPerBeat = 60.0 / bpm / hopSeconds
        let offsetRange = max(1, Int(hopsPerBeat.rounded()))

        var bestOffset = 0
        var bestScore: Double = -.infinity
        for offset in 0..<offsetRange {
            var score: Double = 0
            var beatIndex = 0
            while true {
                let hop = offset + Int((Double(beatIndex) * hopsPerBeat).rounded())
                if hop >= onsets.count { break }
                score += Double(onsets[hop])
                beatIndex += 1
            }
            if score > bestScore {
                bestScore = score
                bestOffset = offset
            }
        }

        var beats: [Double] = []
        var beatIndex = 0
        while true {
            let hop = Double(bestOffset) + Double(beatIndex) * hopsPerBeat
            if hop >= Double(onsets.count) { break }
            beats.append(hop * hopSeconds + onsetLatencySeconds)
            beatIndex += 1
        }
        return beats
    }
}

// MARK: - Downbeat and phrase placement

extension BeatDetector {

    /// Index of the beat to count from, or nil when there is no kick energy
    /// anywhere on the grid to judge the bar by — silence, or audio with no
    /// low end at all. `estimateTempo` will still have produced a grid from
    /// a flat envelope, so without this the caller would get a confidently
    /// placed "one" derived from nothing. Declining lets the UI say it
    /// doesn't know instead.
    static func estimateAnchor(
        features: SpectralFeatures,
        beatTimes: [Double],
        hopSeconds: Double,
        beatsPerMeasure: Int
    ) -> Int? {
        guard let kick = downbeatPhaseScores(
            lowBandOnsets: features.lowBand,
            beatTimes: beatTimes,
            hopSeconds: hopSeconds,
            beatsPerMeasure: beatsPerMeasure
        ) else {
            return nil
        }
        return PhraseAnchor.estimate(
            beatTimes: beatTimes,
            measureScores: kick,
            beatsPerMeasure: beatsPerMeasure,
            spectrogram: features.bands,
            hopSeconds: hopSeconds
        )
    }

    /// Index of the beat most likely to be beat 1, judged by kick energy
    /// alone. See `downbeatPhaseScores` for the vote; this is its winner.
    /// The returned value is an index into `beatTimes`, and is always the
    /// *first* beat of that phase so the anchor sits as early in the clip
    /// as possible.
    static func estimateDownbeatPhase(
        lowBandOnsets: [Float],
        beatTimes: [Double],
        hopSeconds: Double,
        beatsPerMeasure: Int
    ) -> Int? {
        guard let scores = downbeatPhaseScores(
            lowBandOnsets: lowBandOnsets,
            beatTimes: beatTimes,
            hopSeconds: hopSeconds,
            beatsPerMeasure: beatsPerMeasure
        ) else {
            return nil
        }
        return scores.indices.max { scores[$0] < scores[$1] }
    }

    /// Kick energy summed over each phase of the bar.
    ///
    /// Every beat belongs to one of `beatsPerMeasure` phases. Summing
    /// low-band onset strength across each phase picks out the one the
    /// kick lands on, which in practice is the "one" — or the one *and*
    /// the three, which is why `PhraseAnchor` gets the whole vote rather
    /// than just the winner. Nil when there isn't a full bar of beats to
    /// compare, or no kick energy at all.
    static func downbeatPhaseScores(
        lowBandOnsets: [Float],
        beatTimes: [Double],
        hopSeconds: Double,
        beatsPerMeasure: Int
    ) -> [Double]? {
        guard !lowBandOnsets.isEmpty,
              hopSeconds > 0,
              beatsPerMeasure > 0,
              beatTimes.count >= beatsPerMeasure else {
            return nil
        }
        var scores = [Double](repeating: 0, count: beatsPerMeasure)
        for (index, time) in beatTimes.enumerated() {
            scores[index % beatsPerMeasure] += Double(
                strength(of: lowBandOnsets, atBeat: time, hopSeconds: hopSeconds)
            )
        }
        guard scores.contains(where: { $0 > 0 }) else { return nil }
        return scores
    }

    /// Peak envelope value within two frames either side of the frame a
    /// beat at `time` came from.
    ///
    /// The kick's attack is slower than the snare's, so its low-band peak
    /// can trail the broadband onset the beat was placed on by a frame; and
    /// a grid that has been snapped or hand-nudged will not sit on frame
    /// boundaries at all. Sampling a single frame would sometimes read the
    /// trough beside an onset rather than the onset itself.
    private static func strength(
        of envelope: [Float],
        atBeat time: Double,
        hopSeconds: Double
    ) -> Float {
        let centre = frameIndex(forBeatAt: time, hopSeconds: hopSeconds)
        let lower = max(0, centre - 2)
        let upper = min(envelope.count - 1, centre + 2)
        guard lower <= upper else { return 0 }
        return envelope[lower...upper].max() ?? 0
    }
}
