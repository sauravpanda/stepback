@testable import StepBack
import XCTest

/// End-to-end phrase anchoring: synthetic "songs" through the whole
/// detector, checking that the anchor lands on the phrase and not merely
/// the bar. The pure vote is covered in `PhraseAnchorTests`.
final class BeatDetectorPhraseTests: XCTestCase {

    private let bpm: Double = 120

    /// Which beat of the true grid the detector anchored on.
    private func anchorBeat(of analysis: BeatAnalysis) -> Int {
        analysis.downbeatSeconds.map { Int(($0 / (60 / bpm)).rounded()) } ?? -1
    }

    func testAnchorsOnThePhraseStart() {
        // Kick on every bar line; the texture turns over every 32 beats
        // from beat 12. A bar-level anchor would be right about the bar and
        // wrong about the phrase seven times in eight.
        let samples = SyntheticAudio.phrasedTrack(bpm: bpm, phrases: 4, phraseOffset: 12)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: SyntheticAudio.sampleRate)
        let anchor = anchorBeat(of: analysis)
        XCTAssertEqual(anchor % 32, 12, "anchored on beat \(anchor)")
    }

    func testAnchorsOnTheEightWhenSectionsChangeEveryEight() {
        let samples = SyntheticAudio.phrasedTrack(bpm: bpm, phrases: 12, phraseOffset: 4, phraseLength: 8)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: SyntheticAudio.sampleRate)
        let anchor = anchorBeat(of: analysis)
        XCTAssertEqual(anchor % 8, 4, "anchored on beat \(anchor)")
    }

    func testBreaksAKickTieWithTheTexture() {
        // Kick on 1 *and* 3, the common case, so kick energy alone can't
        // tell the bar line from the middle of the bar. Sections start on
        // beat 14 — phase 2 — and that has to settle it.
        let samples = SyntheticAudio.phrasedTrack(bpm: bpm, phrases: 4, phraseOffset: 14, kickPhases: [0, 2])
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: SyntheticAudio.sampleRate)
        let anchor = anchorBeat(of: analysis)
        XCTAssertEqual(anchor % 32, 14, "anchored on beat \(anchor)")
    }

    func testAnchorIsOnTheDetectedGrid() {
        let samples = SyntheticAudio.phrasedTrack(bpm: bpm, phrases: 3, phraseOffset: 20)
        let analysis = BeatDetector.analyzeSamples(samples, sampleRate: SyntheticAudio.sampleRate)
        guard let downbeat = analysis.downbeatSeconds else { return XCTFail("no anchor") }
        XCTAssertTrue(analysis.beatTimes.contains { abs($0 - downbeat) < 1e-9 })
    }
}
