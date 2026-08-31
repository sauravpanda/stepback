import Foundation

/// The ear-training drills offered by the Listen tab.
///
/// Each case is a different question about the same beat grid: *where is
/// one*, *where does the phrase turn over*, and *can you still find one
/// when nothing on screen is helping you*. Config lives here rather than in
/// the views so the drill surface stays presentational.
enum ListeningExercise: String, CaseIterable, Identifiable {
    case findTheOne
    case phraseCatcher
    case countItOut

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .findTheOne: "Find the One"
        case .phraseCatcher: "Phrase Catcher"
        case .countItOut: "Count It Out"
        }
    }

    var blurb: String {
        switch self {
        case .findTheOne:
            "Drops you somewhere random in the track. Tap when you hear beat 1."
        case .phraseCatcher:
            "Tap every time the music turns over into a new 32-count phrase."
        case .countItOut:
            "The counter fades out. Keep counting in your head and tap each 1."
        }
    }

    var systemImage: String {
        switch self {
        case .findTheOne: "target"
        case .phraseCatcher: "waveform.path.ecg"
        case .countItOut: "eye.slash"
        }
    }

    /// Beats per phrase for this drill. `findTheOne` grades against the
    /// measure itself, so it defers to whatever the clip is counted in.
    func phraseLength(beatsPerMeasure: Int) -> Int {
        switch self {
        case .findTheOne: max(1, beatsPerMeasure)
        case .phraseCatcher: 32
        case .countItOut: 8
        }
    }

    /// Catch window as a fraction of one beat. Tighter for `countItOut`
    /// because an internal clock that has drifted half a beat has already
    /// lost the count; looser for `findTheOne`, where landing beyond half a
    /// beat means you picked a different beat entirely, not that you were
    /// sloppy.
    var toleranceFraction: Double {
        switch self {
        case .findTheOne: 0.5
        case .phraseCatcher: PhraseGrid.defaultToleranceFraction
        case .countItOut: 0.35
        }
    }

    /// Whether the drill collects taps across the whole take (`true`) or
    /// grades a single answer and stops (`false`).
    var isContinuous: Bool {
        switch self {
        case .findTheOne: false
        case .phraseCatcher, .countItOut: true
        }
    }

    /// How long a continuous drill runs, in phrases. Nil for single-answer
    /// drills.
    var lengthInPhrases: Int? {
        switch self {
        case .findTheOne: nil
        case .phraseCatcher: 8
        case .countItOut: 8
        }
    }
}

/// What still has to happen before a clip can be drilled against.
///
/// The drills need two things the Practice tab already produces: a beat
/// grid, and a user-placed beat 1. Modelling the gap explicitly lets the
/// Listen tab walk the user through it in place instead of sending them to
/// another tab and hoping they come back.
enum ListeningReadiness: Equatable {
    case needsBeats
    case needsAnchor
    case ready

    init(hasBeatAnalysis: Bool, hasAnchor: Bool) {
        if !hasBeatAnalysis {
            self = .needsBeats
        } else if !hasAnchor {
            self = .needsAnchor
        } else {
            self = .ready
        }
    }

    init(clip: DanceClip) {
        self.init(
            hasBeatAnalysis: clip.hasBeatAnalysis,
            hasAnchor: clip.firstDownbeatSeconds != nil
        )
    }

    var label: String {
        switch self {
        case .needsBeats: "Needs beats"
        case .needsAnchor: "Needs beat 1"
        case .ready: "Ready"
        }
    }

    var systemImage: String {
        switch self {
        case .needsBeats: "waveform"
        case .needsAnchor: "hand.tap"
        case .ready: "checkmark.circle.fill"
        }
    }

    var isReady: Bool {
        self == .ready
    }
}

/// Outcome of a single Find the One answer.
///
/// Two independent questions, because they're different failures: *did you
/// pick the right beat of the measure* (you found the one, or you didn't),
/// and *how tightly did you land on it* (your timing).
struct FindTheOneResult: Equatable {
    let offsetMs: Double
    let measurePosition: Int?

    /// True when the nearest beat to the tap was in fact a downbeat.
    var landedOnOne: Bool {
        measurePosition == 1
    }

    var rating: StepRating {
        StepRating(offsetMs: offsetMs)
    }
}
