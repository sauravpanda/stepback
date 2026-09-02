import Accelerate
import Foundation

// The STFT pass: everything `BeatDetector` reads off the spectrogram, in
// one sweep. Split from the detector proper to keep either file inside
// SwiftLint's length limit; these are ordinary members of `BeatDetector`.

extension BeatDetector {

    /// Everything the detector reads off the spectrogram, from one pass.
    struct SpectralFeatures {
        /// Broadband onset envelope — what tempo and beat tracking run on.
        let full: [Float]
        /// Kick-band onset envelope — what the bar-line vote runs on.
        let lowBand: [Float]
        /// Coarse band levels per frame — what the phrase vote runs on.
        let bands: BandSpectrogram
    }

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

    /// Broadband and low-band onset envelopes from a single STFT pass.
    static func computeOnsetEnvelopes(
        samples: [Float],
        windowSize: Int,
        hopSize: Int,
        lowBandBins: Range<Int>
    ) -> (full: [Float], lowBand: [Float]) {
        let features = computeSpectralFeatures(
            samples: samples,
            windowSize: windowSize,
            hopSize: hopSize,
            lowBandBins: lowBandBins,
            bandBins: []
        )
        return (features.full, features.lowBand)
    }

    /// Onset envelopes and band spectrogram from a **single** STFT pass.
    ///
    /// Tempo wants the whole spectrum, downbeat placement wants only the
    /// kick band, and phrase detection wants a coarse picture of all of it.
    /// Running the FFT once per consumer would triple the cost of analysing
    /// a clip for no reason, so all three are accumulated as the same
    /// spectra are computed. Onset envelopes are half-wave rectified
    /// spectral flux.
    static func computeSpectralFeatures(
        samples: [Float],
        windowSize: Int,
        hopSize: Int,
        lowBandBins: Range<Int>,
        bandBins: [Range<Int>]
    ) -> SpectralFeatures {
        guard let analyser = SpectrumAnalyser(windowSize: windowSize) else {
            return SpectralFeatures(full: [], lowBand: [], bands: BandSpectrogram(bandCount: bandBins.count, linear: []))
        }
        let halfSize = analyser.halfSize
        let lowBand = lowBandBins.clamped(to: 0..<halfSize)
        let bands = bandBins.map { $0.clamped(to: 0..<halfSize) }

        var previousMagnitudes = [Float](repeating: 0, count: halfSize)
        var diff = [Float](repeating: 0, count: halfSize)

        let frameCount = samples.count >= windowSize ? (samples.count - windowSize) / hopSize + 1 : 0
        var onsets: [Float] = []
        var lowOnsets: [Float] = []
        var bandLevels: [Float] = []
        onsets.reserveCapacity(frameCount)
        lowOnsets.reserveCapacity(frameCount)
        bandLevels.reserveCapacity(frameCount * bands.count)

        var pos = 0
        let limit = samples.count - windowSize
        while pos <= limit {
            analyser.analyse(samples, at: pos)
            let magnitudes = analyser.magnitudes

            magnitudes.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                for band in bands {
                    var level: Float = 0
                    if !band.isEmpty {
                        vDSP_sve(base.advanced(by: band.lowerBound), 1, &level, vDSP_Length(band.count))
                    }
                    bandLevels.append(level)
                }
            }

            vDSP_vsub(previousMagnitudes, 1, magnitudes, 1, &diff, 1, vDSP_Length(halfSize))
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
                vDSP_sve(base.advanced(by: lowBand.lowerBound), 1, &lowFlux, vDSP_Length(lowBand.count))
            }

            onsets.append(flux)
            lowOnsets.append(lowFlux)
            previousMagnitudes = magnitudes
            pos += hopSize
        }
        return SpectralFeatures(
            full: normalised(onsets),
            lowBand: normalised(lowOnsets),
            bands: BandSpectrogram(bandCount: bands.count, linear: bandLevels)
        )
    }

    /// FFT bin ranges for `structureBandEdgesHz` at the given resolution.
    static func structureBandBins(sampleRate: Double, windowSize: Int) -> [Range<Int>] {
        let binWidth = sampleRate / Double(windowSize)
        let edges = structureBandEdgesHz.map { Int(($0 / binWidth).rounded()) }
        return zip(edges, edges.dropFirst()).map { lower, upper in
            max(1, lower)..<max(max(1, lower), upper)
        }
    }

    /// Scales an envelope to a 0...1 peak so the two bands are comparable
    /// and thresholds don't depend on absolute loudness.
    private static func normalised(_ envelope: [Float]) -> [Float] {
        guard let peak = envelope.max(), peak > 0 else { return envelope }
        return envelope.map { $0 / peak }
    }

    /// The analysis frame whose onset a beat at `time` came from — the
    /// frame's start sits `onsetLatencySeconds` ahead of the beat.
    static func frameIndex(forBeatAt time: Double, hopSeconds: Double) -> Int {
        Int(((time - onsetLatencySeconds) / hopSeconds).rounded())
    }
}

/// One frame's worth of FFT state — window, setup and scratch buffers —
/// reused across every frame so the hot loop allocates nothing.
private final class SpectrumAnalyser {
    let halfSize: Int
    /// Magnitude spectrum of the most recently analysed frame.
    private(set) var magnitudes: [Float]

    private let windowSize: Int
    private let log2N: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]

    init?(windowSize: Int) {
        let log2N = vDSP_Length(log2(Double(windowSize)).rounded())
        guard let fftSetup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else { return nil }
        self.windowSize = windowSize
        self.halfSize = windowSize / 2
        self.log2N = log2N
        self.fftSetup = fftSetup
        window = [Float](repeating: 0, count: windowSize)
        windowed = [Float](repeating: 0, count: windowSize)
        realp = [Float](repeating: 0, count: halfSize)
        imagp = [Float](repeating: 0, count: halfSize)
        magnitudes = [Float](repeating: 0, count: halfSize)
        vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Windows the frame starting at `position` and leaves its magnitude
    /// spectrum in `magnitudes`.
    func analyse(_ samples: [Float], at position: Int) {
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            vDSP_vmul(base.advanced(by: position), 1, window, 1, &windowed, 1, vDSP_Length(windowSize))
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
    }
}
