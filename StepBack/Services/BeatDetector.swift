import Accelerate
import AVFoundation
import Foundation

struct BeatAnalysis: Equatable {
    let bpm: Double
    let beatTimes: [Double]
    /// Best guess at where beat 1 falls, from low-band onset energy. Nil
    /// when there aren't enough beats to judge. A guess, not gospel — the
    /// UI always leaves the user a way to nudge it.
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
/// Pipeline: audio extraction → onset envelope via spectral flux (STFT) →
/// tempo via autocorrelation of the onset envelope → phase alignment to
/// generate absolute beat times → downbeat placement from low-band onset
/// energy.
///
/// The downbeat is a *guess*, offered so the Listen tab can start counting
/// without making the user place beat 1 by hand. It is wrong often enough
/// that every surface using it must keep a correction one tap away.
enum BeatDetector {

    // MARK: - Tunables

    static let sampleRate: Double = 22_050
    static let windowSize: Int = 1_024
    static let hopSize: Int = 512
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
        let envelopes = computeOnsetEnvelopes(
            samples: samples,
            windowSize: windowSize,
            hopSize: hopSize,
            lowBandBins: kickBins
        )
        let hopSeconds = Double(hopSize) / sampleRate
        let bpm = estimateTempo(onsets: envelopes.full, hopSeconds: hopSeconds)
        let beatTimes = alignBeats(onsets: envelopes.full, bpm: bpm, hopSeconds: hopSeconds)
        let phase = estimateDownbeatPhase(
            lowBandOnsets: envelopes.lowBand,
            beatTimes: beatTimes,
            hopSeconds: hopSeconds,
            beatsPerMeasure: beatsPerMeasure
        )
        return BeatAnalysis(
            bpm: bpm,
            beatTimes: beatTimes,
            downbeatSeconds: phase.flatMap { beatTimes.indices.contains($0) ? beatTimes[$0] : nil }
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

    // MARK: - Onset envelope (half-wave rectified spectral flux)

    /// Broadband onset envelope — what tempo estimation runs on.
    static func computeOnsetEnvelope(
        samples: [Float],
        windowSize: Int,
        hopSize: Int
    ) -> [Float] {
        computeOnsetEnvelopes(
            samples: samples,
            windowSize: windowSize,
            hopSize: hopSize,
            lowBandBins: kickBins
        ).full
    }

    /// Broadband and low-band onset envelopes from a **single** STFT pass.
    ///
    /// Tempo wants the whole spectrum; downbeat placement wants only the
    /// kick band. Running the FFT twice to get them would double the cost
    /// of analysing a clip for no reason, so both are accumulated as the
    /// same spectra are computed.
    static func computeOnsetEnvelopes(
        samples: [Float],
        windowSize: Int,
        hopSize: Int,
        lowBandBins: Range<Int>
    ) -> (full: [Float], lowBand: [Float]) {
        let halfSize = windowSize / 2
        let log2N = vDSP_Length(log2(Double(windowSize)).rounded())
        guard let fftSetup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else {
            return ([], [])
        }
        let lowBand = lowBandBins.clamped(to: 0..<halfSize)
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var window = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

        var windowed = [Float](repeating: 0, count: windowSize)
        var realp = [Float](repeating: 0, count: halfSize)
        var imagp = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)
        var previousMagnitudes = [Float](repeating: 0, count: halfSize)
        var diff = [Float](repeating: 0, count: halfSize)

        var onsets: [Float] = []
        var lowOnsets: [Float] = []
        var pos = 0
        let limit = samples.count - windowSize

        while pos <= limit {
            samples.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                vDSP_vmul(
                    base.advanced(by: pos), 1,
                    window, 1,
                    &windowed, 1,
                    vDSP_Length(windowSize)
                )
            }

            windowed.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                base.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                    realp.withUnsafeMutableBufferPointer { realBuf in
                        imagp.withUnsafeMutableBufferPointer { imagBuf in
                            guard let rBase = realBuf.baseAddress,
                                  let iBase = imagBuf.baseAddress else { return }
                            var split = DSPSplitComplex(realp: rBase, imagp: iBase)
                            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
                            vDSP_fft_zrip(fftSetup, &split, 1, log2N, Int32(FFT_FORWARD))
                            vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
                        }
                    }
                }
            }

            magnitudes.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                var count = Int32(buf.count)
                vvsqrtf(base, base, &count)
            }

            vDSP_vsub(
                previousMagnitudes, 1,
                magnitudes, 1,
                &diff, 1,
                vDSP_Length(halfSize)
            )
            diff.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                var zero: Float = 0
                vDSP_vthr(base, 1, &zero, base, 1, vDSP_Length(buf.count))
            }
            var flux: Float = 0
            var lowFlux: Float = 0
            diff.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                vDSP_sve(base, 1, &flux, vDSP_Length(halfSize))
                guard !lowBand.isEmpty else { return }
                vDSP_sve(
                    base.advanced(by: lowBand.lowerBound), 1,
                    &lowFlux,
                    vDSP_Length(lowBand.count)
                )
            }

            onsets.append(flux)
            lowOnsets.append(lowFlux)
            previousMagnitudes = magnitudes
            pos += hopSize
        }
        return (normalised(onsets), normalised(lowOnsets))
    }

    /// Scales an envelope to a 0...1 peak so the two bands are comparable
    /// and thresholds don't depend on absolute loudness.
    private static func normalised(_ envelope: [Float]) -> [Float] {
        guard let peak = envelope.max(), peak > 0 else { return envelope }
        return envelope.map { $0 / peak }
    }

    // MARK: - Tempo via autocorrelation

    static func estimateTempo(onsets: [Float], hopSeconds: Double) -> Double {
        guard !onsets.isEmpty, hopSeconds > 0 else { return 0 }

        let minLag = max(1, Int((60.0 / maxBPM / hopSeconds).rounded()))
        let maxLag = Int((60.0 / minBPM / hopSeconds).rounded())
        let clampedMaxLag = min(maxLag, onsets.count - 1)
        guard clampedMaxLag > minLag else { return 120 }

        var bestLag = minLag
        var bestScore: Float = -.infinity

        onsets.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for lag in minLag...clampedMaxLag {
                var score: Float = 0
                vDSP_dotpr(
                    base, 1,
                    base.advanced(by: lag), 1,
                    &score,
                    vDSP_Length(onsets.count - lag)
                )
                if score > bestScore {
                    bestScore = score
                    bestLag = lag
                }
            }
        }

        var bpm = 60.0 / (Double(bestLag) * hopSeconds)
        while bpm > foldUpperBound { bpm /= 2 }
        while bpm < foldLowerBound, bpm > 0 { bpm *= 2 }
        return bpm
    }

    // MARK: - Phase alignment

    static func alignBeats(onsets: [Float], bpm: Double, hopSeconds: Double) -> [Double] {
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
            let hop = bestOffset + Int((Double(beatIndex) * hopsPerBeat).rounded())
            if hop >= onsets.count { break }
            beats.append(Double(hop) * hopSeconds)
            beatIndex += 1
        }
        return beats
    }
}

// MARK: - Downbeat placement

/// Split into an extension to keep the enum body under SwiftLint's
/// `type_body_length` limit; these are ordinary members of `BeatDetector`.
extension BeatDetector {

    /// Index of the beat most likely to be beat 1, judged by kick energy.
    ///
    /// Every beat belongs to one of `beatsPerMeasure` phases. Summing
    /// low-band onset strength across each phase and taking the strongest
    /// picks out the one the kick lands on, which in practice is the "one".
    /// Returns nil when there isn't a full measure of beats to compare, in
    /// which case guessing would be noise.
    ///
    /// The returned value is an index into `beatTimes`, and is always the
    /// *first* beat of that phase so the anchor sits as early in the clip
    /// as possible.
    static func estimateDownbeatPhase(
        lowBandOnsets: [Float],
        beatTimes: [Double],
        hopSeconds: Double,
        beatsPerMeasure: Int
    ) -> Int? {
        guard !lowBandOnsets.isEmpty,
              hopSeconds > 0,
              beatsPerMeasure > 0,
              beatTimes.count >= beatsPerMeasure else {
            return nil
        }

        var scores = [Double](repeating: 0, count: beatsPerMeasure)
        for (index, time) in beatTimes.enumerated() {
            scores[index % beatsPerMeasure] += Double(
                strength(of: lowBandOnsets, atTime: time, hopSeconds: hopSeconds)
            )
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return nil }
        // No kick energy anywhere on the grid — silence, or audio with no
        // low end at all. `estimateTempo` will still have produced a beat
        // grid from a flat envelope, so without this the caller would get a
        // confidently-placed "one" derived from nothing. Declining lets the
        // UI say it doesn't know instead.
        guard scores[best] > 0 else { return nil }
        return best
    }

    /// Peak envelope value within one hop either side of `time`.
    ///
    /// `alignBeats` emits beat times on exact hop boundaries, but a beat
    /// grid that has been rescaled or hand-nudged will not be, so sampling
    /// a single index would sometimes read the trough beside an onset
    /// rather than the onset itself.
    private static func strength(
        of envelope: [Float],
        atTime time: Double,
        hopSeconds: Double
    ) -> Float {
        let centre = Int((time / hopSeconds).rounded())
        let lower = max(0, centre - 1)
        let upper = min(envelope.count - 1, centre + 1)
        guard lower <= upper else { return 0 }
        return envelope[lower...upper].max() ?? 0
    }
}
