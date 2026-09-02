import Foundation

/// How a drill is shaped: how much runway before scoring starts, how many
/// phrases get graded, how loose the catch window is, and whether every
/// beat inside the take is a target or only the phrase starts.
struct DrillShape: Equatable {
    /// Phrases played before anything is graded. The lead-in is what makes
    /// the drill fair — catching a phrase change means nothing if you were
    /// never given a chance to find the count first.
    let leadPhrases: Int
    let scoredPhrases: Int
    let toleranceSeconds: Double
    /// True for Tap the Beat: the targets are every beat inside the scored
    /// phrases, not just where each phrase begins.
    let gradesEveryBeat: Bool

    init(leadPhrases: Int, scoredPhrases: Int, toleranceSeconds: Double, gradesEveryBeat: Bool = false) {
        self.leadPhrases = max(1, leadPhrases)
        self.scoredPhrases = max(1, scoredPhrases)
        self.toleranceSeconds = max(0, toleranceSeconds)
        self.gradesEveryBeat = gradesEveryBeat
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
    /// The phrase starts inside the scored window.
    let scoredStarts: [Double]
    /// The moments taps are graded against: the scored phrase starts for a
    /// phrase drill, every beat inside them for Tap the Beat.
    let targets: [Double]
    /// Counter stays visible until here. Equals the first scored phrase,
    /// so Count It Out goes dark exactly when scoring begins.
    let revealUntil: Double
    /// When to stop playback — the last moment a tap could still count,
    /// plus a little headroom so the audio doesn't cut mid-tap.
    let endTime: Double

    init(
        playbackStart: Double,
        scoredStarts: [Double],
        targets: [Double]? = nil,
        revealUntil: Double,
        endTime: Double
    ) {
        self.playbackStart = playbackStart
        self.scoredStarts = scoredStarts
        self.targets = targets ?? scoredStarts
        self.revealUntil = revealUntil
        self.endTime = endTime
    }
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
    ///
    /// `beatTimes` is only consulted when the shape grades every beat: the
    /// targets are then the beats from the first scored phrase start up to
    /// (not including) the phrase after the last scored one — or the end of
    /// the clip, when the take runs into the final phrase.
    static func plan(
        phraseStarts: [Double],
        startIndex: Int,
        shape: DrillShape,
        duration: Double,
        beatTimes: [Double] = []
    ) -> ListeningDrillPlan? {
        guard startIndices(
            phraseCount: phraseStarts.count,
            leadPhrases: shape.leadPhrases
        ).contains(startIndex) else {
            return nil
        }

        let scoredRange = (startIndex + shape.leadPhrases)..<min(
            phraseStarts.count,
            startIndex + shape.leadPhrases + shape.scoredPhrases
        )
        let scored = Array(phraseStarts[scoredRange])
        guard let first = scored.first, let last = scored.last else { return nil }

        var targets = scored
        if shape.gradesEveryBeat {
            let windowEnd = scoredRange.upperBound < phraseStarts.count
                ? phraseStarts[scoredRange.upperBound]
                : duration
            let beats = beatTimes.filter { $0 >= first && $0 < windowEnd }
            if !beats.isEmpty {
                targets = beats
            }
        }

        return ListeningDrillPlan(
            playbackStart: phraseStarts[startIndex],
            scoredStarts: scored,
            targets: targets,
            revealUntil: first,
            endTime: min(duration, (targets.last ?? last) + shape.toleranceSeconds + tailPadding)
        )
    }

    /// A take starting from a random valid phrase, so repeating a drill on
    /// the same clip doesn't just rehearse one spot in the song.
    static func randomPlan(
        phraseStarts: [Double],
        shape: DrillShape,
        duration: Double,
        beatTimes: [Double] = []
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
            duration: duration,
            beatTimes: beatTimes
        )
    }
}

// MARK: - Run state

enum DrillPhase: Equatable {
    case idle
    case running
    case finished
}

/// One target's fate, for the ribbon that fills in as a take runs.
enum PhraseSlotState: Equatable {
    case pending
    /// Caught, and how tightly.
    case hit(StepRating)
    case missed
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
    /// What the most recent tap earned, for feedback in the moment.
    private(set) var lastFeedback: TapFeedback?
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

    /// Records a tap and, when the caller has graded it, what it earned.
    mutating func recordTap(at time: Double, feedback: TapFeedback? = nil) {
        guard phase == .running else { return }
        taps.append(time)
        lastFeedback = feedback
    }

    /// Grades the collected taps against the plan's targets and ends the
    /// take.
    mutating func finish(toleranceSeconds: Double) {
        guard phase == .running, let plan else { return }
        score = PhraseGrid.score(
            taps: taps,
            phraseStarts: plan.targets,
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

    /// One ribbon cell per target at time `now`: caught (and how tightly),
    /// missed, or still to come. Each target reads its nearest tap, so a
    /// double-tap colours one cell rather than two. Empty without a plan.
    func slotStates(at now: Double, toleranceSeconds: Double) -> [PhraseSlotState] {
        guard let plan else { return [] }
        return plan.targets.map { target in
            let nearest = taps.map { $0 - target }.min { abs($0) < abs($1) }
            if let nearest, abs(nearest) <= toleranceSeconds {
                return .hit(StepRating(offsetMs: nearest * 1_000))
            }
            return now > target + toleranceSeconds ? .missed : .pending
        }
    }
}
