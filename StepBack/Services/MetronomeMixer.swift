import AVFoundation
import Foundation

enum MetronomeError: Error, Equatable {
    case noAudioTrack
    case renderFailed
}

/// Mixes an audible click onto a clip's audio, locked to its beat grid.
///
/// The click is **composed into the playable asset** rather than triggered
/// live from the beat-boundary observer. Those observers fire on the main
/// queue with tens of milliseconds of jitter — invisible when it only
/// drives a UI pulse, but plainly audible as a flam when it drives a sound
/// meant to land on the beat. An `AVMutableComposition` puts the music and
/// the clicks on one clock, so they line up by construction.
enum MetronomeMixer {

    /// Click length. Short enough to read as a tick rather than a tone.
    static let clickDuration: Double = 0.04
    static let renderSampleRate: Double = 44_100
    /// Three tiers so the count is legible by ear alone: beat 1 highest,
    /// the other beats mid, the subdivisions between them low and quiet.
    static let downbeatFrequency: Double = 1_600
    static let beatFrequency: Double = 1_000
    static let subdivisionFrequency: Double = 700
    /// Subdivisions sit under the beats rather than competing with them.
    static let subdivisionGainScale: Double = 0.45

    // MARK: - Click track synthesis

    /// Renders a mono click track: one decaying sine burst per beat, pitched
    /// up on downbeats.
    ///
    /// Pure apart from the buffer allocation, so the sample placement can be
    /// checked in tests without touching a file or a player.
    static func renderClickTrack(
        beatTimes: [Double],
        downbeatIndices: Set<Int>,
        duration: Double,
        subdivisionIndices: Set<Int> = [],
        sampleRate: Double = renderSampleRate,
        gain: Double = 0.6
    ) -> [Float] {
        let total = Int((max(0, duration) * sampleRate).rounded())
        guard total > 0 else { return [] }
        var samples = [Float](repeating: 0, count: total)
        let clickSamples = Int(clickDuration * sampleRate)
        guard clickSamples > 0 else { return samples }

        for (index, time) in beatTimes.enumerated() where time >= 0 {
            let start = Int((time * sampleRate).rounded())
            guard start < total else { continue }
            let isSubdivision = subdivisionIndices.contains(index)
            let frequency: Double
            if isSubdivision {
                frequency = subdivisionFrequency
            } else if downbeatIndices.contains(index) {
                frequency = downbeatFrequency
            } else {
                frequency = beatFrequency
            }
            let clickGain = isSubdivision ? gain * subdivisionGainScale : gain
            for offset in 0..<clickSamples {
                let idx = start + offset
                if idx >= total { break }
                let localTime = Double(offset) / sampleRate
                // Steep decay: a click, not a beep. Accumulate rather than
                // assign so overlapping clicks on a dense grid still sum.
                let envelope = exp(-localTime * 90)
                let value = sin(2 * .pi * frequency * localTime) * envelope * clickGain
                samples[idx] += Float(value)
            }
        }
        return samples
    }

    // MARK: - Composition

    /// Builds an asset playing `source`'s audio with the click track mixed
    /// alongside it.
    ///
    /// Video is deliberately not carried over: the Listen tab never shows a
    /// picture, and leaving the track out saves decoding frames nobody
    /// looks at.
    static func composedAsset(
        source: AVAsset,
        beatTimes: [Double],
        downbeatIndices: Set<Int>,
        subdivisionIndices: Set<Int> = []
    ) async throws -> AVAsset {
        let audioTracks = try await source.loadTracks(withMediaType: .audio)
        guard let sourceAudio = audioTracks.first else {
            throw MetronomeError.noAudioTrack
        }
        let duration = try await source.load(.duration)
        let seconds = duration.seconds.isFinite ? duration.seconds : 0
        let range = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        guard let musicTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MetronomeError.renderFailed
        }
        try musicTrack.insertTimeRange(range, of: sourceAudio, at: .zero)

        let clickURL = try writeClickTrack(
            beatTimes: beatTimes,
            downbeatIndices: downbeatIndices,
            duration: seconds,
            subdivisionIndices: subdivisionIndices
        )
        let clickAsset = AVURLAsset(url: clickURL)
        let clickTracks = try await clickAsset.loadTracks(withMediaType: .audio)
        guard let clickSource = clickTracks.first,
              let clickTrack = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw MetronomeError.renderFailed
        }
        let clickDuration = try await clickAsset.load(.duration)
        try clickTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: min(clickDuration, duration)),
            of: clickSource,
            at: .zero
        )
        return composition
    }

    /// Writes the click track to a temporary `.caf` so AVFoundation can
    /// treat it as an ordinary audio track.
    static func writeClickTrack(
        beatTimes: [Double],
        downbeatIndices: Set<Int>,
        duration: Double,
        subdivisionIndices: Set<Int> = []
    ) throws -> URL {
        let samples = renderClickTrack(
            beatTimes: beatTimes,
            downbeatIndices: downbeatIndices,
            duration: duration,
            subdivisionIndices: subdivisionIndices
        )
        guard !samples.isEmpty,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: renderSampleRate,
                  channels: 1
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData else {
            throw MetronomeError.renderFailed
        }
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel[0].update(from: base, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepback-click-\(UUID().uuidString).caf")
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
        return url
    }
}
