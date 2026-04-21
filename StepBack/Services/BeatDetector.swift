import Accelerate
import AVFoundation
import Foundation

struct BeatAnalysis: Equatable {
    let bpm: Double
    let beatTimes: [Double]
}

enum BeatDetectorError: Error, Equatable {
    case noAudioTrack
    case audioExtractionFailed
}

/// On-device beat detector. Apple SDKs only (AVFoundation + Accelerate).
///
/// Pipeline: audio extraction → onset envelope via spectral flux (STFT) →
/// tempo via autocorrelation of the onset envelope → phase alignment to
/// generate absolute beat times. Downbeat anchoring is user-driven (#12)
/// and therefore not attempted here.
enum BeatDetector {

    // MARK: - Tunables

    static let sampleRate: Double = 22_050
    static let windowSize: Int = 1_024
    static let hopSize: Int = 512
    static let minBPM: Double = 60
    static let maxBPM: Double = 200
    static let foldLowerBound: Double = 75
    static let foldUpperBound: Double = 160

    // MARK: - Public API

    static func analyze(asset: AVAsset) async throws -> BeatAnalysis {
        let samples = try await extractMonoFloatSamples(from: asset)
        return analyzeSamples(samples, sampleRate: sampleRate)
    }

    /// Pure entry point: feed a float-mono PCM buffer, get back BPM + beats.
    /// Exposed for tests and for future live-analysis experiments.
    static func analyzeSamples(_ samples: [Float], sampleRate: Double) -> BeatAnalysis {
        guard samples.count >= windowSize else {
            return BeatAnalysis(bpm: 0, beatTimes: [])
        }
        let onsets = computeOnsetEnvelope(
            samples: samples,
            windowSize: windowSize,
            hopSize: hopSize
        )
        let hopSeconds = Double(hopSize) / sampleRate
        let bpm = estimateTempo(onsets: onsets, hopSeconds: hopSeconds)
        let beatTimes = alignBeats(onsets: onsets, bpm: bpm, hopSeconds: hopSeconds)
        return BeatAnalysis(bpm: bpm, beatTimes: beatTimes)
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

    // swiftlint:disable:next function_body_length
    static func computeOnsetEnvelope(
        samples: [Float],
        windowSize: Int,
        hopSize: Int
    ) -> [Float] {
        let halfSize = windowSize / 2
        let log2N = vDSP_Length(log2(Double(windowSize)).rounded())
        guard let fftSetup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else {
            return []
        }
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

            var sqrtCount = Int32(halfSize)
            vvsqrtf(&magnitudes, &magnitudes, &sqrtCount)

            vDSP_vsub(
                previousMagnitudes, 1,
                magnitudes, 1,
                &diff, 1,
                vDSP_Length(halfSize)
            )
            var zero: Float = 0
            vDSP_vthr(diff, 1, &zero, &diff, 1, vDSP_Length(halfSize))
            var flux: Float = 0
            vDSP_sve(diff, 1, &flux, vDSP_Length(halfSize))

            onsets.append(flux)
            previousMagnitudes = magnitudes
            pos += hopSize
        }

        if let peak = onsets.max(), peak > 0 {
            onsets = onsets.map { $0 / peak }
        }
        return onsets
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
