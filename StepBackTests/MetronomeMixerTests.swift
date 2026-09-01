@testable import StepBack
import XCTest

final class MetronomeMixerTests: XCTestCase {

    private let sampleRate = MetronomeMixer.renderSampleRate

    private func index(atSecond second: Double) -> Int {
        Int((second * sampleRate).rounded())
    }

    /// Peak absolute amplitude in a short window starting at `second`.
    private func energy(in samples: [Float], atSecond second: Double, window: Int = 40) -> Float {
        let start = index(atSecond: second)
        guard start >= 0, start < samples.count else { return 0 }
        let end = min(samples.count - 1, start + window)
        return samples[start...end].map(abs).max() ?? 0
    }

    // MARK: - Placement

    func testClicksLandOnTheBeatTimes() {
        let samples = MetronomeMixer.renderClickTrack(
            beatTimes: [0, 0.5, 1.0],
            downbeatIndices: [0],
            duration: 2
        )
        XCTAssertGreaterThan(energy(in: samples, atSecond: 0), 0.1)
        XCTAssertGreaterThan(energy(in: samples, atSecond: 0.5), 0.1)
        XCTAssertGreaterThan(energy(in: samples, atSecond: 1.0), 0.1)
    }

    func testSilenceBetweenClicks() {
        let samples = MetronomeMixer.renderClickTrack(
            beatTimes: [0, 0.5, 1.0],
            downbeatIndices: [0],
            duration: 2
        )
        // A third of a second past the last click, the tail has decayed out.
        XCTAssertEqual(energy(in: samples, atSecond: 1.4), 0, accuracy: 1e-4)
    }

    func testTrackIsExactlyTheRequestedLength() {
        let samples = MetronomeMixer.renderClickTrack(
            beatTimes: [0], downbeatIndices: [], duration: 1.5
        )
        XCTAssertEqual(samples.count, index(atSecond: 1.5))
    }

    // MARK: - Accents

    func testDownbeatsClickAtADifferentPitch() {
        let accented = MetronomeMixer.renderClickTrack(
            beatTimes: [0, 0.5], downbeatIndices: [0], duration: 1
        )
        let first = Array(accented[0..<40])
        let second = Array(accented[index(atSecond: 0.5)..<(index(atSecond: 0.5) + 40)])
        XCTAssertNotEqual(first, second, "beat 1 should be audibly distinct from the others")
    }

    func testEveryBeatClicksWhenNothingIsAccented() {
        let samples = MetronomeMixer.renderClickTrack(
            beatTimes: [0, 0.5], downbeatIndices: [], duration: 1
        )
        let first = Array(samples[0..<40])
        let second = Array(samples[index(atSecond: 0.5)..<(index(atSecond: 0.5) + 40)])
        XCTAssertEqual(first, second)
    }

    // MARK: - Degenerate input

    func testZeroDurationRendersNothing() {
        XCTAssertTrue(
            MetronomeMixer.renderClickTrack(
                beatTimes: [0, 1], downbeatIndices: [], duration: 0
            ).isEmpty
        )
    }

    func testBeatsPastTheEndAreIgnored() {
        let samples = MetronomeMixer.renderClickTrack(
            beatTimes: [0, 99], downbeatIndices: [], duration: 1
        )
        XCTAssertEqual(samples.count, index(atSecond: 1))
        XCTAssertGreaterThan(energy(in: samples, atSecond: 0), 0.1)
    }

    func testNegativeBeatTimesAreSkipped() {
        let samples = MetronomeMixer.renderClickTrack(
            beatTimes: [-1, 0.5], downbeatIndices: [], duration: 1
        )
        XCTAssertGreaterThan(energy(in: samples, atSecond: 0.5), 0.1)
        XCTAssertEqual(energy(in: samples, atSecond: 0), 0, accuracy: 1e-4)
    }

    func testNoBeatsRendersSilenceOfTheRightLength() {
        let samples = MetronomeMixer.renderClickTrack(
            beatTimes: [], downbeatIndices: [], duration: 1
        )
        XCTAssertEqual(samples.count, index(atSecond: 1))
        XCTAssertEqual(samples.map(abs).max() ?? 0, 0, accuracy: 1e-6)
    }

    // MARK: - File output

    func testWritesAPlayableClickFile() throws {
        let url = try MetronomeMixer.writeClickTrack(
            beatTimes: [0, 0.5], downbeatIndices: [0], duration: 1
        )
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let size = try FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    // MARK: - Scratch file lifecycle

    func testEachRenderGetsItsOwnFile() throws {
        // Distinct URLs matter: the old file has to stay readable until the
        // player has actually switched off it.
        let first = try MetronomeMixer.writeClickTrack(
            beatTimes: [0, 0.5], downbeatIndices: [0], duration: 1
        )
        let second = try MetronomeMixer.writeClickTrack(
            beatTimes: [0, 0.5], downbeatIndices: [0], duration: 1
        )
        defer {
            MetronomeMixer.discardClickTrack(at: first)
            MetronomeMixer.discardClickTrack(at: second)
        }
        XCTAssertNotEqual(first, second)
    }

    func testDiscardRemovesTheFile() throws {
        let url = try MetronomeMixer.writeClickTrack(
            beatTimes: [0], downbeatIndices: [], duration: 1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        MetronomeMixer.discardClickTrack(at: url)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "click tracks run to tens of megabytes; leaving them behind fills the temp directory"
        )
    }

    func testDiscardIsSafeOnNilAndMissingFiles() {
        // Called on teardown paths where there may never have been a file.
        MetronomeMixer.discardClickTrack(at: nil)
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepback-click-does-not-exist.caf")
        MetronomeMixer.discardClickTrack(at: absent)
    }
}
