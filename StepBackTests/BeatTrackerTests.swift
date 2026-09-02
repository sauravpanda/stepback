@testable import StepBack
import XCTest

final class BeatTrackerTests: XCTestCase {

    // MARK: - Fixtures

    /// Synthetic onset envelope: a narrow triangular spike centred on each
    /// (fractional) frame in `beatFrames`, so sub-frame refinement has a
    /// shape to fit.
    private func envelope(beatFrames: [Double], frameCount: Int) -> [Float] {
        var onsets = [Float](repeating: 0, count: frameCount)
        for frame in beatFrames {
            let centre = Int(frame.rounded())
            for offset in -2...2 {
                let index = centre + offset
                guard index >= 0, index < frameCount else { continue }
                let distance = abs(frame - Double(index))
                onsets[index] += Float(max(0, 1 - distance / 1.5))
            }
        }
        return onsets
    }

    private func assertEveryBeatTracked(
        _ truth: [Double],
        by tracked: [Int],
        within frames: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for beat in truth {
            let nearest = tracked.map { abs(Double($0) - beat) }.min() ?? .infinity
            XCTAssertLessThanOrEqual(
                nearest, frames,
                "no tracked beat within \(frames) frames of \(beat)", file: file, line: line
            )
        }
    }

    // MARK: - Tracking

    func testTracksAConstantGrid() {
        let truth = (0..<40).map { Double($0) * 43.3 + 5 }
        let onsets = envelope(beatFrames: truth, frameCount: 1_800)
        let tracked = BeatTracker.track(onsets: onsets, period: 43.3)

        XCTAssertEqual(tracked.count, truth.count, accuracy: 1)
        assertEveryBeatTracked(truth, by: tracked, within: 1)
    }

    func testFollowsAGradualTempoChange() {
        // Period stretches from 40 to 48 frames across sixty beats — a 20%
        // slow-down, far more than any drift the lattice fit tolerates.
        var truth: [Double] = [10]
        for beat in 1..<60 {
            truth.append(truth[beat - 1] + 40 + 8 * Double(beat) / 60)
        }
        let onsets = envelope(beatFrames: truth, frameCount: Int(truth.last ?? 0) + 60)
        let tracked = BeatTracker.track(onsets: onsets, period: 44)

        XCTAssertEqual(tracked.count, truth.count, accuracy: 1)
        assertEveryBeatTracked(truth, by: tracked, within: 1)
    }

    func testCoastsThroughAGapAtTheExpectedTempo() {
        // Ten beats of silence in the middle. The lattice on either side is
        // the same one, so the tracker should bridge it with beats at the
        // expected spacing rather than stopping or doubling up.
        let period = 43.0
        let truth = (0..<50).filter { $0 < 20 || $0 >= 30 }.map { Double($0) * period + 5 }
        let onsets = envelope(beatFrames: truth, frameCount: 2_300)
        let tracked = BeatTracker.track(onsets: onsets, period: period)

        XCTAssertEqual(tracked.count, 50, accuracy: 1)
        let inGap = tracked.filter { Double($0) > 20 * period && Double($0) < 30 * period }
        XCTAssertEqual(inGap.count, 10, accuracy: 1, "gap should be bridged, was \(inGap)")
        for (previous, next) in zip(tracked, tracked.dropFirst()) {
            XCTAssertEqual(Double(next - previous), period, accuracy: 2.5)
        }
    }

    func testDoesNotStartInLeadingSilence() {
        let truth = (0..<20).map { Double($0) * 43 + 500 }
        let onsets = envelope(beatFrames: truth, frameCount: 1_500)
        let tracked = BeatTracker.track(onsets: onsets, period: 43)

        XCTAssertGreaterThanOrEqual(tracked.first ?? 0, 495, "chain started in silence: \(tracked.prefix(3))")
    }

    func testSilenceTracksNothing() {
        XCTAssertEqual(BeatTracker.track(onsets: [Float](repeating: 0, count: 500), period: 43), [])
        XCTAssertEqual(BeatTracker.track(onsets: [], period: 43), [])
    }

    // MARK: - Refinement

    func testRefineRecoversASubFramePosition() {
        let onsets = envelope(beatFrames: [100.3], frameCount: 200)
        let refined = BeatTracker.refine(frames: [100], onsets: onsets)
        XCTAssertEqual(refined[0], 100.3, accuracy: 0.15)
    }

    func testRefineLooksOneFrameEitherSideForThePeak() {
        // The tracker's smoothing can park a beat next to the raw peak.
        let onsets = envelope(beatFrames: [100.0], frameCount: 200)
        XCTAssertEqual(BeatTracker.refine(frames: [101], onsets: onsets)[0], 100, accuracy: 0.05)
        XCTAssertEqual(BeatTracker.refine(frames: [99], onsets: onsets)[0], 100, accuracy: 0.05)
    }

    func testRefineLeavesAFlatFrameAlone() {
        let onsets = [Float](repeating: 0.2, count: 50)
        XCTAssertEqual(BeatTracker.refine(frames: [10], onsets: onsets), [10])
    }

    // MARK: - Lattice fit

    /// Deterministic pseudo-random jitter in `-amplitude...amplitude`.
    private func jitter(_ index: Int, amplitude: Double) -> Double {
        let phase = Double((index * 7_919) % 1_000) / 1_000
        return (phase * 2 - 1) * amplitude
    }

    func testLatticeFitRecoversTheGridFromJitteredBeats() {
        let times = (0..<80).map { 1.234 + 0.4876 * Double($0) + jitter($0, amplitude: 0.004) }
        let lattice = BeatTracker.fitLattice(beatTimes: times)

        XCTAssertNotNil(lattice)
        XCTAssertEqual(lattice?.period ?? 0, 0.4876, accuracy: 0.0005)
        XCTAssertEqual(lattice?.firstBeat ?? 0, 1.234, accuracy: 0.005)
    }

    func testLatticeFitRejectsDrift() {
        // Quadratic drift: nearly a second off the straight line by the end.
        let times = (0..<60).map { Double($0) * 0.5 + 0.0003 * Double($0 * $0) }
        XCTAssertNil(BeatTracker.fitLattice(beatTimes: times))
    }

    func testLatticeFitIgnoresAFewCoastingBeats() {
        // Eight beats in the middle sit 60ms off the grid — the tracker
        // coasting through a break at a slightly wrong tempo. They must not
        // tilt the fit, and must not stop the grid being recognised.
        let times = (0..<60).map { index -> Double in
            let onGrid = Double(index) * 0.5
            return (20..<28).contains(index) ? onGrid + 0.06 : onGrid
        }
        let lattice = BeatTracker.fitLattice(beatTimes: times)

        XCTAssertNotNil(lattice)
        XCTAssertEqual(lattice?.period ?? 0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(lattice?.firstBeat ?? 0, 0, accuracy: 1e-6)
    }

    func testLatticeFitNeedsEnoughBeats() {
        XCTAssertNil(BeatTracker.fitLattice(beatTimes: [0, 0.5, 1.0, 1.5]))
    }

    func testLatticeTimesCoverTheRange() {
        let lattice = BeatTracker.Lattice(firstBeat: 1.0, period: 0.5)
        let times = lattice.times(covering: 0...2.2)
        XCTAssertEqual(times.count, 5)
        for (actual, expected) in zip(times, [0.0, 0.5, 1.0, 1.5, 2.0]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-9)
        }
    }

    // MARK: - Extension

    func testExtendedFillsBothEnds() {
        let extended = BeatTracker.extended(beatTimes: [2.0, 2.5, 3.0], toCover: 0...4.2)
        XCTAssertEqual(extended.count, 9)
        for (actual, expected) in zip(extended, stride(from: 0.0, through: 4.0, by: 0.5)) {
            XCTAssertEqual(actual, expected, accuracy: 1e-9)
        }
    }

    func testExtendedLeavesASingleBeatAlone() {
        XCTAssertEqual(BeatTracker.extended(beatTimes: [1.0], toCover: 0...4), [1.0])
    }

    func testMedianInterval() {
        XCTAssertEqual(BeatTracker.medianInterval([0, 0.5, 1.0, 1.6, 2.1]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BeatTracker.medianInterval([1.0]), 0)
    }
}
