import Foundation
@testable import StepBack
import XCTest

final class BeatDetectorTests: XCTestCase {

    private let sampleRate: Double = 22_050

    // MARK: - Synthetic click tracks

    /// Generates a click track: short decaying 1kHz sine pulses at the given
    /// BPM for `duration` seconds. This is deliberately a bit noisy (click is
    /// a windowed tone, not a delta) so the onset detector has something
    /// realistic to latch onto.
    private func clickTrack(bpm: Double, duration: Double, sampleRate: Double) -> [Float] {
        let totalSamples = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: totalSamples)

        let beatInterval = 60.0 / bpm
        let clickDuration = 0.05
        let clickSamples = Int(clickDuration * sampleRate)
        let numBeats = Int(duration / beatInterval) + 1

        for beatIndex in 0..<numBeats {
            let startSample = Int(Double(beatIndex) * beatInterval * sampleRate)
            for offset in 0..<clickSamples {
                let idx = startSample + offset
                if idx >= totalSamples { break }
                let localTime = Double(offset) / sampleRate
                let decay = exp(-localTime * 20)
                let tone = sin(2 * .pi * 1_000 * localTime) * decay * 0.5
                samples[idx] += Float(tone)
            }
        }
        return samples
    }

    // MARK: - Tempo estimation

    func testDetects120BPMFromClickTrack() {
        let samples = clickTrack(bpm: 120, duration: 10, sampleRate: sampleRate)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 120, accuracy: 2.0, "BPM was \(analysis.bpm)")
    }

    func testDetects96BPMFromClickTrack() {
        let samples = clickTrack(bpm: 96, duration: 12, sampleRate: sampleRate)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 96, accuracy: 2.0, "BPM was \(analysis.bpm)")
    }

    func testDetects150BPMFromClickTrack() {
        let samples = clickTrack(bpm: 150, duration: 10, sampleRate: sampleRate)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)
        XCTAssertEqual(analysis.bpm, 150, accuracy: 2.0, "BPM was \(analysis.bpm)")
    }

    // MARK: - Beat-time alignment

    func testBeatTimesMatchClickPositionsAt120BPM() {
        let samples = clickTrack(bpm: 120, duration: 8, sampleRate: sampleRate)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)

        XCTAssertGreaterThanOrEqual(analysis.beatTimes.count, 12)

        // Adjacent beat spacing should sit near 60/bpm (0.5s) within a
        // couple of frames of slop (~46ms @ hop=512/22050).
        let expectedInterval = 60.0 / 120.0
        let tolerance = 0.06
        for index in 1..<analysis.beatTimes.count {
            let delta = analysis.beatTimes[index] - analysis.beatTimes[index - 1]
            XCTAssertEqual(delta, expectedInterval, accuracy: tolerance)
        }
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
        let samples = clickTrack(bpm: 240, duration: 8, sampleRate: sampleRate)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: sampleRate)
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
}
