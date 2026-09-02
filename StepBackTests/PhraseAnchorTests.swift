@testable import StepBack
import XCTest

final class PhraseAnchorTests: XCTestCase {

    private let hopSeconds = 0.05
    private let beatSeconds = 0.5
    private let bandCount = 4

    // MARK: - Fixtures

    /// One feature vector per beat. Beats are grouped into blocks of
    /// `blockLength`, the first block boundary falling at `offset`; every
    /// block has a distinct texture — one band loud, the rest quiet.
    private func blockFeatures(beats: Int, blockLength: Int, offset: Int) -> [[Float]] {
        (0..<beats).map { beat in
            let block = Int((Double(beat - offset) / Double(blockLength)).rounded(.down))
            let loudBand = ((block % bandCount) + bandCount) % bandCount
            return (0..<bandCount).map { $0 == loudBand ? Float(-10) : Float(-40) }
        }
    }

    /// The same texture as `blockFeatures`, as a spectrogram at ten frames
    /// per beat, so `estimate` can be driven end to end.
    private func blockSpectrogram(beats: Int, blockLength: Int, offset: Int) -> BandSpectrogram {
        let features = blockFeatures(beats: beats, blockLength: blockLength, offset: offset)
        let framesPerBeat = Int(beatSeconds / hopSeconds)
        var linear: [Float] = []
        for feature in features {
            for _ in 0..<framesPerBeat {
                linear.append(contentsOf: feature.map { pow(10, $0 / 20) })
            }
        }
        return BandSpectrogram(bandCount: bandCount, linear: linear)
    }

    private func beatTimes(_ count: Int) -> [Double] {
        (0..<count).map { Double($0) * beatSeconds }
    }

    // MARK: - Novelty

    func testNoveltyPeaksExactlyWhereTheTextureChanges() {
        let features = blockFeatures(beats: 128, blockLength: 32, offset: 12)
        let peaks = PhraseAnchor.peaks(in: PhraseAnchor.novelty(features: features, halfWidth: 8))

        let found = peaks.indices.filter { peaks[$0] > 0 }
        XCTAssertEqual(found, [12, 44, 76, 108])
    }

    func testNoveltyIsZeroWithoutAFullWindowEitherSide() {
        let features = blockFeatures(beats: 48, blockLength: 32, offset: 4)
        let novelty = PhraseAnchor.novelty(features: features, halfWidth: 8)
        XCTAssertEqual(novelty[4], 0, "change at 4 has no eight beats before it")
        XCTAssertGreaterThan(novelty[36], 0)
        XCTAssertEqual(novelty[41], 0, "no eight beats after 41 either")
    }

    func testPeaksDropTheRampEitherSideOfAChange() {
        // Block averaging smears each change into a ramp; only its apex
        // may count, or the vote learns nothing.
        let features = blockFeatures(beats: 64, blockLength: 32, offset: 20)
        let novelty = PhraseAnchor.novelty(features: features, halfWidth: 8)
        XCTAssertGreaterThan(novelty[19], 0)
        XCTAssertGreaterThan(novelty[21], 0)
        let peaks = PhraseAnchor.peaks(in: novelty)
        XCTAssertEqual(peaks[19], 0)
        XCTAssertGreaterThan(peaks[20], 0)
        XCTAssertEqual(peaks[21], 0)
    }

    // MARK: - Voting

    func testVoteCreditsTheCombThePeaksFallOn() {
        var peaks = [Double](repeating: 0, count: 64)
        peaks[5] = 1
        peaks[13] = 1
        peaks[29] = 2

        let vote = PhraseAnchor.vote(peaks: peaks, base: 1, step: 1, candidates: 4, stride: 4)
        XCTAssertEqual(vote.scores, [4, 0, 0, 0], "base 1 + candidate 0 claims 1, 5, 9, ...")
        XCTAssertEqual(vote.best, 0)
    }

    func testVoteTiesGoToTheEarliestCandidate() {
        XCTAssertEqual(PhraseAnchor.Vote(scores: [2, 2, 1]).best, 0)
        XCTAssertEqual(PhraseAnchor.Vote(scores: [0, 0]).best, 0)
    }

    func testVoteConfidence() {
        XCTAssertEqual(PhraseAnchor.Vote(scores: [3, 1]).confidence, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(PhraseAnchor.Vote(scores: [2, 2]).confidence, 0)
        XCTAssertEqual(PhraseAnchor.Vote(scores: [0, 0]).confidence, 0)
        XCTAssertEqual(PhraseAnchor.Vote(scores: [5]).confidence, 1)
    }

    func testNormalisedSumsToOneAndLeavesZerosAlone() {
        XCTAssertEqual(PhraseAnchor.normalised([1, 3]), [0.25, 0.75])
        XCTAssertEqual(PhraseAnchor.normalised([0, 0]), [0, 0])
    }

    // MARK: - Estimate

    func testEstimateFindsThePhraseStart() {
        // Kick on every fourth beat from 0; texture changes every 32 beats
        // from beat 12. The anchor must be a bar line (≡ 0 mod 4) *and* a
        // phrase start (≡ 12 mod 32) — i.e. 12.
        let anchor = PhraseAnchor.estimate(
            beatTimes: beatTimes(140),
            measureScores: [1, 0, 0, 0],
            beatsPerMeasure: 4,
            spectrogram: blockSpectrogram(beats: 140, blockLength: 32, offset: 12),
            hopSeconds: hopSeconds
        )
        XCTAssertEqual(anchor, 12)
    }

    func testTextureBreaksAKickTieBetweenTheOneAndTheThree() {
        // Kick on 1 and 3 is the common case and leaves the kick vote
        // split 50/50 between phases 0 and 2. Sections start on 14, which
        // is phase 2 — texture change should settle it.
        let anchor = PhraseAnchor.estimate(
            beatTimes: beatTimes(140),
            measureScores: [1, 0, 1, 0],
            beatsPerMeasure: 4,
            spectrogram: blockSpectrogram(beats: 140, blockLength: 32, offset: 14),
            hopSeconds: hopSeconds
        )
        XCTAssertEqual(anchor, 14)
    }

    func testEstimateStopsAtTheEightWhenSectionsChangeEveryEight() {
        // Texture changes every 8 beats from beat 4: every 8-count start is
        // equally a boundary, so the 32 vote ties and the anchor stays on
        // the first 8-count start it found.
        let anchor = PhraseAnchor.estimate(
            beatTimes: beatTimes(140),
            measureScores: [1, 0, 0, 0],
            beatsPerMeasure: 4,
            spectrogram: blockSpectrogram(beats: 140, blockLength: 8, offset: 4),
            hopSeconds: hopSeconds
        )
        XCTAssertEqual((anchor ?? -1) % 8, 4)
    }

    func testEstimateFallsBackToTheBarOnAShortClip() {
        let anchor = PhraseAnchor.estimate(
            beatTimes: beatTimes(6),
            measureScores: [0, 0, 1, 0],
            beatsPerMeasure: 4,
            spectrogram: blockSpectrogram(beats: 6, blockLength: 32, offset: 0),
            hopSeconds: hopSeconds
        )
        XCTAssertEqual(anchor, 2)
    }

    func testEstimateFallsBackToTheEightWhenShorterThanAPhrase() {
        // Twenty-four beats: room for the 8-count vote, not the 32.
        let anchor = PhraseAnchor.estimate(
            beatTimes: beatTimes(24),
            measureScores: [1, 0, 0, 0],
            beatsPerMeasure: 4,
            spectrogram: blockSpectrogram(beats: 24, blockLength: 8, offset: 4),
            hopSeconds: hopSeconds
        )
        XCTAssertEqual(anchor, 4)
    }

    func testEstimateNeedsABarOfBeats() {
        XCTAssertNil(
            PhraseAnchor.estimate(
                beatTimes: beatTimes(3),
                measureScores: [1, 0, 0, 0],
                beatsPerMeasure: 4,
                spectrogram: blockSpectrogram(beats: 3, blockLength: 32, offset: 0),
                hopSeconds: hopSeconds
            )
        )
    }

    func testEstimateWithNoTextureChangeFollowsTheKick() {
        // Uniform texture: no peaks anywhere, so the kick vote stands and
        // the finer levels leave the anchor where it is.
        let uniform = BandSpectrogram(
            bandCount: bandCount,
            linear: [Float](repeating: 0.5, count: 140 * 10 * bandCount)
        )
        let anchor = PhraseAnchor.estimate(
            beatTimes: beatTimes(140),
            measureScores: [0, 0, 0, 1],
            beatsPerMeasure: 4,
            spectrogram: uniform,
            hopSeconds: hopSeconds
        )
        XCTAssertEqual(anchor, 3)
    }

    // MARK: - Spectrogram

    func testBandSpectrogramIsInDecibelsBelowThePeak() {
        let spectrogram = BandSpectrogram(bandCount: 2, linear: [1.0, 0.1, 0.001, 0])
        XCTAssertEqual(spectrogram.frameCount, 2)
        XCTAssertEqual(spectrogram[0, 0], 0, accuracy: 1e-5)
        XCTAssertEqual(spectrogram[0, 1], -20, accuracy: 1e-4)
        XCTAssertEqual(spectrogram[1, 0], -60, accuracy: 1e-4)
        XCTAssertEqual(spectrogram[1, 1], BandSpectrogram.floorDecibels, accuracy: 1e-4)
    }

    func testBandSpectrogramOfSilenceIsFlat() {
        let spectrogram = BandSpectrogram(bandCount: 2, linear: [0, 0, 0, 0])
        XCTAssertEqual(spectrogram.decibels, [0, 0, 0, 0])
    }

    func testBeatFeaturesAverageTheFramesOfEachBeat() {
        let spectrogram = blockSpectrogram(beats: 4, blockLength: 2, offset: 0)
        let features = PhraseAnchor.beatFeatures(
            spectrogram: spectrogram,
            beatTimes: beatTimes(4),
            hopSeconds: hopSeconds
        )
        // Levels are relative to the clip's loudest band-frame, so the loud
        // band reads 0 dB and the quiet one 30 dB under it.
        XCTAssertEqual(features.count, 4)
        XCTAssertEqual(features[0][0], 0, accuracy: 1e-3)
        XCTAssertEqual(features[0][1], -30, accuracy: 1e-3)
        XCTAssertEqual(features[2][1], 0, accuracy: 1e-3)
    }
}
