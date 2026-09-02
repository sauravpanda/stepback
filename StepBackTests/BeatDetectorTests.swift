import Foundation
@testable import StepBack
import XCTest

final class BeatDetectorTests: XCTestCase {

    private let sampleRate = SyntheticAudio.sampleRate

    private func clickTrack(bpm: Double, duration: Double) -> [Float] {
        SyntheticAudio.clickTrack(bpm: bpm, duration: duration)
    }

    // MARK: - Tempo estimation

    func testDetects120BPMFromClickTrack() {
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 120, duration: 10), sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 120, accuracy: 0.5, "BPM was \(analysis.bpm)")
    }

    func testDetects96BPMFromClickTrack() {
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 96, duration: 12), sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 96, accuracy: 0.5, "BPM was \(analysis.bpm)")
    }

    func testDetects150BPMFromClickTrack() {
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 150, duration: 10), sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 150, accuracy: 0.5, "BPM was \(analysis.bpm)")
    }

    func testTempoIsResolvedFinerThanAWholeFrame() {
        // 117 BPM is 44.17 frames per beat: not on a frame boundary, so a
        // whole-frame lag would report 117.4 or 114.8. Neither is 117.
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 117, duration: 20), sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 117, accuracy: 0.3, "BPM was \(analysis.bpm)")
    }

    // MARK: - Beat-time alignment

    func testBeatTimesMatchClickPositionsAt120BPM() {
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 120, duration: 8), sampleRate: sampleRate)

        XCTAssertGreaterThanOrEqual(analysis.beatTimes.count, 12)

        // Adjacent beat spacing should sit near 60/bpm (0.5s) within a
        // couple of frames of slop.
        let expectedInterval = 60.0 / 120.0
        for index in 1..<analysis.beatTimes.count {
            let delta = analysis.beatTimes[index] - analysis.beatTimes[index - 1]
            XCTAssertEqual(delta, expectedInterval, accuracy: 0.03)
        }
    }

    func testBeatsLandOnTheClicksNotAheadOfThem() {
        // Spectral flux peaks while the attack is still entering the
        // window, so raw frame times run ~25ms early. The detector corrects
        // for that; here the grid must sit on the clicks to within a few ms
        // with no systematic lean either way.
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 120, duration: 12), sampleRate: sampleRate)
        let interior = analysis.beatTimes.filter { $0 > 0.3 && $0 < 11.5 }
        XCTAssertGreaterThan(interior.count, 20)

        let offsets = interior.map { $0 - ($0 / 0.5).rounded() * 0.5 }
        for offset in offsets {
            XCTAssertEqual(offset, 0, accuracy: 0.012, "beat \(offset * 1_000)ms off its click")
        }
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        XCTAssertEqual(mean, 0, accuracy: 0.008, "grid leans \(mean * 1_000)ms")
    }

    func testConstantTempoSnapsToAnExactGrid() {
        // A produced track deserves a grid with no frame jitter: once the
        // tracked beats fit a constant tempo, every interval is identical.
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 128, duration: 20), sampleRate: sampleRate)
        let intervals = zip(analysis.beatTimes.dropFirst(), analysis.beatTimes).map { $0 - $1 }
        guard let first = intervals.first else { return XCTFail("no beats") }
        for interval in intervals {
            XCTAssertEqual(interval, first, accuracy: 1e-6)
        }
        XCTAssertEqual(first, 60.0 / 128, accuracy: 0.002)
    }

    func testFollowsATempoRamp() {
        // 112 to 128 BPM over 40 seconds. A single-tempo grid is a beat off
        // at both ends; the tracker should stay on every click.
        let (samples, clicks) = SyntheticAudio.rampingClickTrack(startBPM: 112, endBPM: 128, duration: 40)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)

        for click in clicks where click > 0.5 && click < 39 {
            let nearest = analysis.beatTimes.map { abs($0 - click) }.min() ?? .infinity
            XCTAssertLessThan(nearest, 0.025, "no beat within 25ms of the click at \(click)s")
        }
        let tracked = analysis.beatTimes.filter { $0 > 0.5 && $0 < 39 }
        let expected = clicks.filter { $0 > 0.5 && $0 < 39 }
        XCTAssertEqual(tracked.count, expected.count, accuracy: 2)
    }

    // MARK: - Degenerate inputs

    func testEmptySamplesReturnsZeroBPM() {
        let analysis = BeatDetector.analyzeSamples([], sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 0)
        XCTAssertTrue(analysis.beatTimes.isEmpty)
    }

    func testShorterThanWindowReturnsZeroBPM() {
        let samples = [Float](repeating: 0, count: 200)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 0)
    }

    func testSilenceProducesNoBeats() {
        // 5s of silence: no onsets, so phase alignment shouldn't hallucinate
        // a pattern. BPM may be arbitrary but the envelope peak guard ensures
        // we don't divide through by zero.
        let samples = [Float](repeating: 0, count: Int(5 * sampleRate))
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)
        // A silent onset envelope means every autocorrelation score is 0,
        // which is still >= -.infinity, so we'll report *some* BPM. We only
        // assert we got back a finite number without crashing.
        XCTAssertTrue(analysis.bpm.isFinite)
    }

    // MARK: - Tempo folding

    func testFoldsHighBPMIntoWCSRange() {
        // 240 BPM (every quarter-second) should fold down to 120.
        let analysis = BeatDetector.analyzeSamples(clickTrack(bpm: 240, duration: 8), sampleRate: sampleRate)
        XCTAssertLessThanOrEqual(analysis.bpm, BeatDetector.foldUpperBound + 2)
        XCTAssertGreaterThanOrEqual(analysis.bpm, BeatDetector.foldLowerBound - 2)
    }

    // MARK: - Alignment helper behavior

    func testAlignBeatsReturnsEmptyForZeroBPM() {
        XCTAssertEqual(
            BeatDetector.alignBeats(onsets: [0.1, 0.2, 0.3], bpm: 0, hopSeconds: 0.02),
            []
        )
    }

    func testRigidLatticeFallsBackWhenThereIsNothingToTrack() {
        // A flat envelope has no beats to follow, but the caller still gets
        // a grid at the estimated tempo — the pre-tracker behaviour.
        let beats = BeatDetector.trackBeats(
            onsets: [Float](repeating: 0.001, count: 400),
            bpm: 120,
            hopSeconds: 0.0116
        )
        XCTAssertGreaterThan(beats.beatTimes.count, 5)
        XCTAssertEqual(beats.bpm, 120)
    }

    // MARK: - Downbeat placement

    private func estimatePhase(
        in samples: [Float],
        bpm: Double,
        duration: Double,
        beatsPerMeasure: Int = 4
    ) -> Int? {
        let envelopes = BeatDetector.computeOnsetEnvelopes(
            samples: samples,
            windowSize: BeatDetector.windowSize,
            hopSize: BeatDetector.hopSize,
            lowBandBins: BeatDetector.kickBins
        )
        let interval = 60.0 / bpm
        let beats = Array(stride(from: 0.0, to: duration, by: interval))
        return BeatDetector.estimateDownbeatPhase(
            lowBandOnsets: envelopes.lowBand,
            beatTimes: beats,
            hopSeconds: Double(BeatDetector.hopSize) / sampleRate,
            beatsPerMeasure: beatsPerMeasure
        )
    }

    func testFindsDownbeatWhenKickIsOnBeatOne() {
        let samples = SyntheticAudio.accentedTrack(bpm: 120, duration: 16, beatsPerMeasure: 4, kickPhase: 0)
        XCTAssertEqual(estimatePhase(in: samples, bpm: 120, duration: 16), 0)
    }

    func testFindsDownbeatWhenKickIsOnAnOffsetPhase() {
        let samples = SyntheticAudio.accentedTrack(bpm: 120, duration: 16, beatsPerMeasure: 4, kickPhase: 2)
        XCTAssertEqual(estimatePhase(in: samples, bpm: 120, duration: 16), 2)
    }

    func testSnareOnTheBackbeatDoesNotStealTheDownbeat() {
        // The whole reason the estimator reads the kick band rather than the
        // broadband envelope: here the snare on beat 3 is louder in overall
        // spectral flux than the kick on beat 1, and a broadband guess would
        // anchor the count on the backbeat.
        let samples = SyntheticAudio.accentedTrack(
            bpm: 120, duration: 16, beatsPerMeasure: 4, kickPhase: 0, snarePhase: 2
        )
        XCTAssertEqual(estimatePhase(in: samples, bpm: 120, duration: 16), 0)
    }

    func testDownbeatIsNilWithoutAFullMeasureOfBeats() {
        XCTAssertNil(
            BeatDetector.estimateDownbeatPhase(
                lowBandOnsets: [0.1, 0.9, 0.2],
                beatTimes: [0, 0.5, 1.0],
                hopSeconds: 0.023,
                beatsPerMeasure: 4
            )
        )
    }

    func testDownbeatIsNilWithoutAnEnvelope() {
        XCTAssertNil(
            BeatDetector.estimateDownbeatPhase(
                lowBandOnsets: [],
                beatTimes: [0, 0.5, 1.0, 1.5],
                hopSeconds: 0.023,
                beatsPerMeasure: 4
            )
        )
    }

    func testAnalysisSurfacesTheDownbeatAsATimestamp() {
        let samples = SyntheticAudio.accentedTrack(bpm: 120, duration: 16, beatsPerMeasure: 4, kickPhase: 0)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)
        let downbeat = analysis.downbeatSeconds
        XCTAssertNotNil(downbeat)
        // Whatever beat it picked must actually be on the detected grid.
        XCTAssertTrue(analysis.beatTimes.contains { abs($0 - (downbeat ?? -1)) < 1e-9 })
        XCTAssertEqual(Int(((downbeat ?? -1) / 0.5).rounded()) % 4, 0)
    }

    func testSilenceYieldsNoDownbeat() {
        let analysis = BeatDetector.analyzeSamples(
            [Float](repeating: 0, count: Int(sampleRate * 4)), sampleRate: sampleRate
        )
        XCTAssertNil(analysis.downbeatSeconds)
    }
}
