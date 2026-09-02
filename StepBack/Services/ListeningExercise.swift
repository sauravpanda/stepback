import Foundation

/// The ear-training drills offered by the Listen tab, in ladder order.
///
/// Each case is a different question about the same beat grid, from the
/// most basic up: *can you tap the beat at all*, *where is one*, *where
/// does the phrase turn over*, and *can you still find one when nothing on
/// screen is helping you*. Config lives here rather than in the views so
/// the drill surface stays presentational.
enum ListeningExercise: String, CaseIterable, Identifiable {
    case tapTheBeat
    case findTheOne
    case phraseCatcher
    case countItOut

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tapTheBeat: "Tap the Beat"
        case .findTheOne: "Find the One"
        case .phraseCatcher: "Phrase Catcher"
        case .countItOut: "Count It Out"
        }
    }

    var blurb: String {
        switch self {
        case .tapTheBeat:
            "Tap along with every beat. Each tap tells you early or late, so your hands learn the beat before your ear does."
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
        case .tapTheBeat: "hand.tap"
        case .findTheOne: "target"
        case .phraseCatcher: "waveform.path.ecg"
        case .countItOut: "eye.slash"
        }
    }

    /// What the tap pad asks for while a take is running.
    var tapPrompt: String {
        switch self {
        case .tapTheBeat: "on every beat"
        case .findTheOne: "on beat 1"
        case .phraseCatcher: "on every 1 of the phrase"
        case .countItOut: "on every 1 of the 8"
        }
    }

    /// Beats per phrase for this drill — the unit a take is planned in.
    /// `findTheOne` grades against the measure itself, so it defers to
    /// whatever the clip is counted in. `tapTheBeat` runs in 8s so a take
    /// starts on a count of 1 and lasts a round number of 8s.
    func phraseLength(beatsPerMeasure: Int) -> Int {
        switch self {
        case .tapTheBeat: 8
        case .findTheOne: max(1, beatsPerMeasure)
        case .phraseCatcher: 32
        case .countItOut: 8
        }
    }

    /// Catch window as a fraction of one beat. Tighter for `countItOut`
    /// because an internal clock that has drifted half a beat has already
    /// lost the count; looser for `findTheOne`, where landing beyond half a
    /// beat means you picked a different beat entirely, not that you were
    /// sloppy. Half a beat for `tapTheBeat` too: every tap is then within
    /// reach of *some* beat, so nothing is a stray — the drill is about how
    /// tight you are, not whether you hit.
    var toleranceFraction: Double {
        switch self {
        case .tapTheBeat: 0.5
        case .findTheOne: 0.5
        case .phraseCatcher: PhraseGrid.defaultToleranceFraction
        case .countItOut: 0.35
        }
    }

    /// Whether every beat inside the take is a target, rather than only the
    /// phrase starts. Only Tap the Beat asks about the beat itself.
    var gradesEveryBeat: Bool {
        self == .tapTheBeat
    }

    /// Whether the drill collects taps across the whole take (`true`) or
    /// grades a single answer and stops (`false`).
    var isContinuous: Bool {
        switch self {
        case .findTheOne: false
        case .tapTheBeat, .phraseCatcher, .countItOut: true
        }
    }

    /// How long a continuous drill runs, in phrases. Nil for single-answer
    /// drills. Four 8s of beat-tapping is long enough to settle into and
    /// short enough to go again straight away.
    var lengthInPhrases: Int? {
        switch self {
        case .tapTheBeat: 4
        case .findTheOne: nil
        case .phraseCatcher, .countItOut: 8
        }
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
