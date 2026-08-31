import Foundation

/// How a drill is shaped: how much runway before scoring starts, how many
/// phrases get graded, and how loose the catch window is.
struct DrillShape: Equatable {
    /// Phrases played before anything is graded. The lead-in is what makes
    /// the drill fair — catching a phrase change means nothing if you were
    /// never given a chance to find the count first.
    let leadPhrases: Int
    let scoredPhrases: Int
    let toleranceSeconds: Double

    init(leadPhrases: Int, scoredPhrases: Int, toleranceSeconds: Double) {
        self.leadPhrases = max(1, leadPhrases)
        self.scoredPhrases = max(1, scoredPhrases)
        self.toleranceSeconds = max(0, toleranceSeconds)
    }
}

/// A single runnable take of a listening drill.
///
/// Splitting this out of the view keeps the scheduling arithmetic — where
/// playback starts, which phrases count, when the counter goes dark —
/// testable without an AVPlayer, the same way `BeatGrid` and `PhraseGrid`
/// are.
struct ListeningDrillPlan: Equatable {
    /// Where playback starts. Always on a phrase boundary, so the dancer
    /// hears the phrase begin rather than being dropped into its middle.
    let playbackStart: Double
    /// The phrase starts that actually get graded.
    let scoredStarts: [Double]
    /// Counter stays visible until here. Equals the first scored phrase,
    /// so Count It Out goes dark exactly when scoring begins.
    let revealUntil: Double
    /// When to stop playback — the last moment a tap could still count,
    /// plus a little headroom so the audio doesn't cut mid-tap.
    let endTime: Double
}

enum ListeningDrillPlanner {

    /// Trailing headroom after the final scoreable tap, in seconds.
    static let tailPadding: Double = 0.25

    /// Phrase indices a take could start from — those with enough phrases
    /// left after them to cover the lead-in plus at least one scored
    /// phrase. Empty when the clip is too short to drill.
    static func startIndices(phraseCount: Int, leadPhrases: Int) -> Range<Int> {
        let last = phraseCount - max(1, leadPhrases)
        guard last > 0 else { return 0..<0 }
        return 0..<last
    }

    /// Builds a take beginning at `startIndex`.
    static func plan(
        phraseStarts: [Double],
        startIndex: Int,
        shape: DrillShape,
        duration: Double
    ) -> ListeningDrillPlan? {
        guard startIndices(
            phraseCount: phraseStarts.count,
            leadPhrases: shape.leadPhrases
        ).contains(startIndex) else {
            return nil
        }

        let scored = Array(
            phraseStarts[(startIndex + shape.leadPhrases)...].prefix(shape.scoredPhrases)
        )
        guard let first = scored.first, let last = scored.last else { return nil }

        return ListeningDrillPlan(
            playbackStart: phraseStarts[startIndex],
            scoredStarts: scored,
            revealUntil: first,
            endTime: min(duration, last + shape.toleranceSeconds + tailPadding)
        )
    }

    /// A take starting from a random valid phrase, so repeating a drill on
    /// the same clip doesn't just rehearse one spot in the song.
    static func randomPlan(
        phraseStarts: [Double],
        shape: DrillShape,
        duration: Double
    ) -> ListeningDrillPlan? {
        let candidates = startIndices(
            phraseCount: phraseStarts.count,
            leadPhrases: shape.leadPhrases
        )
        guard let startIndex = candidates.randomElement() else { return nil }
        return plan(
            phraseStarts: phraseStarts,
            startIndex: startIndex,
            shape: shape,
            duration: duration
        )
    }
}

// MARK: - Run state

enum DrillPhase: Equatable {
    case idle
    case running
    case finished
}

/// Mutable state of one drill run.
///
/// Lives outside the view so the transitions — start, tap, finish, bail
/// out on a clip that's too short — can be exercised in tests instead of
/// only on a phone with music playing.
struct ListeningDrillState: Equatable {

    private(set) var phase: DrillPhase = .idle
    private(set) var plan: ListeningDrillPlan?
    private(set) var taps: [Double] = []
    private(set) var score: PhraseScore?
    private(set) var oneShot: FindTheOneResult?
    private(set) var planError: String?

    /// Back to square one, keeping nothing from the previous take.
    mutating func reset() {
        self = ListeningDrillState()
    }

    /// Starts a scored take. Clears the previous result first so a stale
    /// score can never be shown next to a live run.
    mutating func begin(plan: ListeningDrillPlan) {
        reset()
        self.plan = plan
        phase = .running
    }

    /// Starts an open-ended take with no phrase schedule — Find the One,
    /// which ends when the dancer answers rather than at a fixed time.
    mutating func beginOpenEnded() {
        reset()
        phase = .running
    }

    mutating func fail(_ message: String) {
        reset()
        planError = message
    }

    mutating func recordTap(at time: Double) {
        guard phase == .running else { return }
        taps.append(time)
    }

    /// Grades the collected taps against the plan and ends the take.
    mutating func finish(toleranceSeconds: Double) {
        guard phase == .running, let plan else { return }
        score = PhraseGrid.score(
            taps: taps,
            phraseStarts: plan.scoredStarts,
            toleranceSeconds: toleranceSeconds
        )
        phase = .finished
    }

    mutating func answer(_ result: FindTheOneResult) {
        guard phase == .running else { return }
        oneShot = result
        phase = .finished
    }

    /// Whether playback has run past the end of the scored window.
    func hasRunOut(at time: Double) -> Bool {
        guard phase == .running, let plan else { return false }
        return time >= plan.endTime
    }
}
