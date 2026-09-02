import Foundation

/// Synthetic test signals for the beat detector: click tracks, accented
/// bars and phrased "songs", all rendered at the detector's sample rate.
/// Shared by the detector test classes so each stays inside SwiftLint's
/// body-length limit.
enum SyntheticAudio {

    static let sampleRate: Double = 22_050

    /// Adds a decaying sine burst to `samples` starting at `start`.
    static func addBurst(
        _ samples: inout [Float],
        start: Int,
        frequency: Double,
        decay: Double,
        length: Double,
        amplitude: Double = 0.9
    ) {
        let count = Int(length * sampleRate)
        for offset in 0..<count {
            let idx = start + offset
            guard idx >= 0, idx < samples.count else { break }
            let localTime = Double(offset) / sampleRate
            samples[idx] += Float(sin(2 * .pi * frequency * localTime) * exp(-localTime * decay) * amplitude)
        }
    }

    /// Adds a steady sine tone from `start` for `length` seconds.
    static func addTone(_ samples: inout [Float], start: Int, frequency: Double, length: Double, amplitude: Double) {
        let count = Int(length * sampleRate)
        for offset in 0..<count {
            let idx = start + offset
            guard idx >= 0, idx < samples.count else { break }
            samples[idx] += Float(sin(2 * .pi * frequency * Double(offset) / sampleRate) * amplitude)
        }
    }

    /// Renders a click at each of `clicks` (seconds): short decaying 1kHz
    /// sine pulses. Deliberately a bit noisy (a windowed tone, not a delta)
    /// so the onset detector has something realistic to latch onto.
    static func render(clicks: [Double], duration: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(duration * sampleRate))
        for click in clicks {
            addBurst(
                &samples,
                start: Int(click * sampleRate),
                frequency: 1_000, decay: 20, length: 0.05, amplitude: 0.5
            )
        }
        return samples
    }

    /// A click track at a constant BPM for `duration` seconds.
    static func clickTrack(bpm: Double, duration: Double) -> [Float] {
        let beatInterval = 60.0 / bpm
        let numBeats = Int(duration / beatInterval) + 1
        return render(clicks: (0..<numBeats).map { Double($0) * beatInterval }, duration: duration)
    }

    /// A click track whose tempo glides from `startBPM` to `endBPM` across
    /// `duration`. Returns the exact click times alongside the audio.
    static func rampingClickTrack(
        startBPM: Double,
        endBPM: Double,
        duration: Double
    ) -> (samples: [Float], clicks: [Double]) {
        var clicks: [Double] = []
        var time = 0.0
        while time < duration {
            clicks.append(time)
            let bpm = startBPM + (endBPM - startBPM) * (time / duration)
            time += 60 / bpm
        }
        return (render(clicks: clicks, duration: duration), clicks)
    }

    /// Click track where each beat gets a plain 1 kHz tick, plus an
    /// optional accent on one phase of the measure. Kick accents (60Hz)
    /// land in the low band the downbeat estimator reads; snare accents
    /// (3kHz) sit well above it.
    static func accentedTrack(
        bpm: Double,
        duration: Double,
        beatsPerMeasure: Int,
        kickPhase: Int?,
        snarePhase: Int? = nil
    ) -> [Float] {
        var samples = clickTrack(bpm: bpm, duration: duration)
        let beatInterval = 60.0 / bpm
        let beats = Int(duration / beatInterval) + 1

        for beatIndex in 0..<beats {
            let phase = beatIndex % beatsPerMeasure
            let start = Int(Double(beatIndex) * beatInterval * sampleRate)
            if phase == kickPhase {
                addBurst(&samples, start: start, frequency: 60, decay: 8, length: 0.12)
            }
            if phase == snarePhase {
                addBurst(&samples, start: start, frequency: 3_000, decay: 30, length: 0.12)
            }
        }
        return samples
    }

    /// A produced-music stand-in: a click on every beat, a kick on the given
    /// phases of every bar, and a sustained tone whose pitch changes every
    /// `phraseLength` beats from beat `phraseOffset` onwards — the texture
    /// change a real phrase boundary carries. Beats before the first phrase
    /// start get a tone of their own, like an intro.
    static func phrasedTrack(
        bpm: Double,
        phrases: Int,
        phraseOffset: Int,
        phraseLength: Int = 32,
        kickPhases: Set<Int> = [0]
    ) -> [Float] {
        let interval = 60 / bpm
        let beats = phraseOffset + phrases * phraseLength
        let duration = Double(beats) * interval
        var samples = render(clicks: (0..<beats).map { Double($0) * interval }, duration: duration)
        let tones: [Double] = [4_000, 500, 1_500, 3_000, 800, 2_200]

        for beat in 0..<beats {
            let start = Int(Double(beat) * interval * sampleRate)
            let phrase = beat >= phraseOffset ? (beat - phraseOffset) / phraseLength + 1 : 0
            addTone(&samples, start: start, frequency: tones[phrase % tones.count], length: interval, amplitude: 0.12)
            let phase = ((beat - phraseOffset) % 4 + 4) % 4
            if kickPhases.contains(phase) {
                addBurst(&samples, start: start, frequency: 60, decay: 8, length: 0.12)
            }
        }
        return samples
    }
}
