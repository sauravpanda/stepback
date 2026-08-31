import AVFoundation
import SwiftData
import SwiftUI

/// One clip, one player, every listening drill.
///
/// Setup (detect beats, place beat 1) and the drills themselves share this
/// screen deliberately: they need the same loaded asset, and a dancer who
/// has just anchored beat 1 should be able to drill it immediately rather
/// than navigating back out and in again.
struct ListeningDrillView: View {

    let clip: DanceClip

    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: PracticePlayerViewModel

    @State private var exercise: ListeningExercise = .phraseCatcher
    @State private var run = ListeningDrillState()
    @State private var revealPhrases: Int = 2

    init(clip: DanceClip) {
        self.clip = clip
        _vm = StateObject(
            wrappedValue: PracticePlayerViewModel(
                assetIdentifier: clip.assetIdentifier,
                cloudIdentifier: clip.cloudAssetIdentifier,
                localFileURL: clip.preferredLocalFileURL,
                onLocalIdentifierRemapped: { healed in
                    clip.assetIdentifier = healed
                    try? clip.modelContext?.save()
                }
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if readiness.isReady {
                    drillSection
                } else {
                    ListeningSetupCard(
                        readiness: readiness,
                        isPlaying: vm.isPlaying,
                        onTogglePlay: vm.togglePlayPause,
                        onTapBeatOne: tapOnBeatOne
                    )
                }
            }
            .padding(16)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle(clip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .keepScreenAwake()
        .task {
            await vm.load()
            configureBeatPulse()
        }
        .onDisappear { vm.pause() }
        .onChange(of: vm.currentTime) { _, now in
            guard run.hasRunOut(at: now) else { return }
            vm.pause()
            run.finish(toleranceSeconds: tolerance)
        }
        .onChange(of: exercise) { _, _ in
            vm.pause()
            run.reset()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            BPMBadge(
                bpm: clip.bpm,
                isAnalyzing: vm.isAnalyzingBeats,
                measurePosition: nil,
                beatsPerMeasure: clip.beatsPerMeasure,
                onDetect: { Task { await detectBeats() } },
                beatPulseID: vm.beatPulseID,
                lastBeatWasDownbeat: vm.lastBeatWasDownbeat
            )
            if let error = vm.loadError ?? vm.analysisError {
                Text(error)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Color(hex: 0xFF5F5F))
            }
        }
    }

    // MARK: - Drill

    private var drillSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExercisePicker(selected: exercise) { exercise = $0 }

            Text(exercise.blurb)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)

            if exercise == .countItOut, run.phase == .idle {
                difficultyStepper
            }

            PhraseCounter(
                position: counterPosition,
                phraseLength: counterLength,
                isRevealed: counterRevealed,
                pulseID: vm.beatPulseID
            )
            .frame(maxWidth: .infinity)

            if let plan = run.plan, run.phase != .idle {
                PhraseRibbon(states: slotStates(for: plan))
            }

            tapTarget

            if let planError = run.planError {
                Text(planError)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Color(hex: 0xFF5F5F))
            }

            results
            reanchorButton
        }
    }

    private var difficultyStepper: some View {
        Stepper(value: $revealPhrases, in: 1...4) {
            Text("Counter visible for \(revealPhrases) × 8 before it goes dark")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .tint(Theme.Color.accent)
    }

    @ViewBuilder
    private var tapTarget: some View {
        if run.phase == .running {
            BigTapTarget(
                title: "Tap",
                subtitle: exercise == .findTheOne ? "on beat 1" : "on every 1 of the phrase",
                isEnabled: true,
                onTap: recordTap
            )
        } else {
            BigTapTarget(
                title: run.phase == .finished ? "Go again" : "Start",
                subtitle: exercise.title,
                isEnabled: true,
                onTap: start
            )
        }
    }

    @ViewBuilder
    private var results: some View {
        if let oneShot = run.oneShot {
            FindTheOneCard(result: oneShot, onRetry: start)
        } else if let score = run.score {
            DrillResultsCard(score: score, onRetry: start)
        }
    }

    private var reanchorButton: some View {
        Button(action: clearDownbeat) {
            Text("Re-anchor beat 1")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived state

    private var readiness: ListeningReadiness {
        ListeningReadiness(clip: clip)
    }

    private var tolerance: Double {
        PhraseGrid.toleranceSeconds(
            bpm: clip.bpm ?? 0,
            fractionOfBeat: exercise.toleranceFraction
        )
    }

    /// The counter reads in 8s for both phrase drills. An 8-count doesn't
    /// give the 32-count phrase away — it repeats four times inside one —
    /// so it stays an honest aid rather than the answer.
    private var counterLength: Int {
        exercise == .findTheOne ? max(1, clip.beatsPerMeasure) : 8
    }

    private var counterPosition: Int? {
        PhraseGrid.phrasePosition(
            currentTime: vm.currentTime,
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            phraseLength: counterLength
        )
    }

    private var counterRevealed: Bool {
        switch exercise {
        case .findTheOne:
            // Showing the count would simply answer the question.
            false
        case .phraseCatcher:
            true
        case .countItOut:
            run.plan.map { vm.currentTime < $0.revealUntil } ?? true
        }
    }

    /// Live indicator only, and approximate on purpose: it marks any phrase
    /// with a tap inside the window as caught, whereas the final
    /// `PhraseGrid.score` resolves double-taps properly.
    private func slotStates(for plan: ListeningDrillPlan) -> [PhraseSlotState] {
        let now = vm.currentTime
        let window = tolerance
        return plan.scoredStarts.map { start in
            if run.taps.contains(where: { abs($0 - start) <= window }) {
                return .hit
            }
            return now > start + window ? .missed : .pending
        }
    }
}

// MARK: - Drill lifecycle

/// Lifecycle and persistence live in extensions purely to keep the view's
/// own body readable — the declarations are still private to this file.
private extension ListeningDrillView {

    func start() {
        if exercise == .findTheOne {
            startFindTheOne()
        } else {
            startContinuous()
        }
    }

    func startContinuous() {
        let starts = PhraseGrid.phraseStartTimes(
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            phraseLength: exercise.phraseLength(beatsPerMeasure: clip.beatsPerMeasure)
        )
        let shape = DrillShape(
            leadPhrases: exercise == .countItOut ? revealPhrases : 1,
            scoredPhrases: exercise.lengthInPhrases ?? 1,
            toleranceSeconds: tolerance
        )
        guard let plan = ListeningDrillPlanner.randomPlan(
            phraseStarts: starts,
            shape: shape,
            duration: vm.duration
        ) else {
            run.fail("This clip is too short for a \(exercise.title) take. Try a longer one.")
            return
        }
        run.begin(plan: plan)
        vm.seek(to: plan.playbackStart)
        vm.play()
    }

    func startFindTheOne() {
        guard !clip.beatTimes.isEmpty else {
            run.fail("No beat grid on this clip yet.")
            return
        }
        // Leave a few seconds of runway so the drop-in isn't right at the
        // end of the clip with nothing left to listen to.
        let latest = max(0.01, vm.duration - 6)
        run.beginOpenEnded()
        vm.seek(to: Double.random(in: 0...latest))
        vm.play()
    }

    func recordTap() {
        if exercise == .findTheOne {
            answerFindTheOne()
        } else {
            run.recordTap(at: vm.precisePlaybackTime)
        }
    }

    func answerFindTheOne() {
        let time = vm.precisePlaybackTime
        vm.pause()
        run.answer(
            FindTheOneResult(
                offsetMs: BeatGrid.offsetMs(from: time, toNearestBeatIn: clip.beatTimes) ?? 0,
                measurePosition: PhraseGrid.phrasePosition(
                    currentTime: time,
                    beatTimes: clip.beatTimes,
                    anchor: clip.firstDownbeatSeconds,
                    phraseLength: max(1, clip.beatsPerMeasure)
                )
            )
        )
    }
}

// MARK: - Model writes

private extension ListeningDrillView {

    func detectBeats() async {
        await vm.detectBeats(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
    }

    func tapOnBeatOne() {
        vm.tapOnBeatOne(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
    }

    func clearDownbeat() {
        vm.pause()
        run.reset()
        vm.clearDownbeatAnchor(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
    }

    func configureBeatPulse() {
        vm.configureBeatPulse(
            beatTimes: clip.beatTimes,
            downbeatIndices: BeatGrid.downbeatIndices(
                beatTimes: clip.beatTimes,
                anchor: clip.firstDownbeatSeconds,
                beatsPerMeasure: clip.beatsPerMeasure
            )
        )
    }
}
