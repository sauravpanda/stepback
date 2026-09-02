import AVFoundation
import SwiftData
import SwiftUI

/// A music player that happens to know where the beat is.
///
/// Everything the old drill screen made you set up by hand now happens on
/// arrival: the beat grid is detected in the background and beat 1 is placed
/// from kick energy, so opening a clip starts music and a live count with no
/// taps at all. The estimate is sometimes a beat off, so correction sits
/// permanently on screen rather than behind a setup step.
///
/// Playback never waits on analysis — press play and the music starts; the
/// beat furniture appears when the grid lands.
struct ListeningPlayerView: View {

    /// Beats per phrase for transport and looping. A full 32-count phrase is
    /// the unit dancers navigate by — and the unit the detector anchors on.
    static let phraseLength = PhraseAnchor.phraseLength
    /// The counter reads in 8s. That repeats four times inside a phrase, so
    /// it helps without giving the phrase boundary away.
    static let countLength = PhraseAnchor.countLength

    let clip: DanceClip

    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: PracticePlayerViewModel

    @AppStorage(SettingsKeys.countSubdivision) private var subdivisionRaw = CountSubdivision.quarter.rawValue

    @State private var metronomeOn = false
    /// Scratch file behind the current click mix, held so it can be deleted
    /// once the player has moved off it.
    @State private var clickTrackURL: URL?
    @State private var isSwitchingAudio = false
    @State private var drillsShown = false
    /// Opens on the bottom rung of the ladder: someone who can't yet hear
    /// the beat should meet the beat first, not the phrase.
    @State private var exercise: ListeningExercise = .tapTheBeat
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
            VStack(alignment: .leading, spacing: 18) {
                counterBlock
                timeline
                PhraseTransport(
                    isPlaying: vm.isPlaying,
                    isEnabled: hasGrid,
                    onPrevious: { seekPhrase(forward: false) },
                    onTogglePlay: vm.togglePlayPause,
                    onNext: { seekPhrase(forward: true) }
                )
                .frame(maxWidth: .infinity)
                chips
                playbackSettings
                AnchorNudgeBar(
                    hasAnchor: clip.firstDownbeatSeconds != nil,
                    onShift: shiftAnchor,
                    onTapBeatOne: tapOnBeatOne
                )
                if drillsShown {
                    DrillPanel(
                        exercise: exercise,
                        run: run,
                        slotStates: run.slotStates(at: vm.currentTime, toleranceSeconds: tolerance),
                        revealPhrases: $revealPhrases,
                        onSelectExercise: { newValue in
                            exercise = newValue
                            vm.pause()
                            run.reset()
                        },
                        onStart: startDrill,
                        onTap: recordDrillTap
                    )
                }
                if let error = vm.loadError ?? vm.analysisError {
                    Text(error)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Color(hex: 0xFF5F5F))
                }
            }
            .padding(16)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle(clip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ListeningMoreMenu(isAnalyzing: vm.isAnalyzingBeats) {
                    Task { await redetectBeats() }
                }
            }
        }
        .keepScreenAwake()
        .task { await prepare() }
        .onDisappear {
            vm.pause()
            MetronomeMixer.discardClickTrack(at: clickTrackURL)
            clickTrackURL = nil
        }
        .onChange(of: vm.currentTime) { _, now in
            guard run.hasRunOut(at: now) else { return }
            vm.pause()
            run.finish(toleranceSeconds: tolerance)
        }
    }

    // MARK: - Sections

    /// The count is redrawn from the display clock rather than from
    /// `vm.currentTime`.
    ///
    /// The view model publishes on a 0.1s periodic observer, which is fine
    /// for a scrubber but cannot render subdivisions: a sixteenth at 120 BPM
    /// lasts 0.125s and at 160 BPM only 0.09s, so slots would be skipped
    /// outright. `TimelineView` samples `precisePlaybackTime` straight from
    /// the player instead, and pauses itself when nothing is playing.
    private var counterBlock: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !vm.isPlaying)) { _ in
            counterContent(at: vm.precisePlaybackTime)
        }
    }

    private func counterContent(at time: Double) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let bpm = clip.bpm, bpm > 0 {
                    Text("\(Int(bpm.rounded())) BPM")
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.Color.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.Color.accentSoft, in: Capsule())
                }
                if vm.isAnalyzingBeats {
                    AnalyzingBanner()
                }
                Spacer()
            }
            // Pinned: this row is empty before analysis lands and gains a
            // chip afterwards, which would otherwise jog the whole screen
            // down the moment the beat grid arrives.
            .frame(height: 30)
            PhraseCounter(
                position: countPosition(at: time),
                spoken: spokenCount(at: time),
                phraseLength: Self.countLength,
                isRevealed: counterRevealed,
                pulseID: vm.beatPulseID
            )
            CountRow(
                beatsPerRow: Self.countLength,
                subdivision: subdivision,
                currentBeat: countPosition(at: time),
                currentSlot: slotIndex(at: time)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            PlayerScrubber(
                currentTime: vm.currentTime,
                duration: vm.duration,
                loopStart: vm.loopStart,
                loopEnd: vm.loopEnd,
                beatTimes: clip.beatTimes,
                downbeatIndices: phraseIndices,
                onSeek: vm.seek
            )
            HStack {
                Text(LibraryFormatter.position(vm.currentTime))
                Spacer()
                Text(LibraryFormatter.duration(vm.duration))
            }
            .font(Theme.Font.timestamp)
            .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            PlayerToggleChip(
                title: "Loop phrase",
                systemImage: "repeat",
                isOn: vm.loopStart != nil,
                isEnabled: hasGrid,
                action: toggleLoopPhrase
            )
            PlayerToggleChip(
                title: "Click",
                systemImage: metronomeOn ? "metronome.fill" : "metronome",
                isOn: metronomeOn,
                isEnabled: hasGrid && !isSwitchingAudio,
                action: { Task { await toggleMetronome() } }
            )
            PlayerToggleChip(
                title: "Drills",
                systemImage: "target",
                isOn: drillsShown,
                isEnabled: hasGrid,
                action: { drillsShown.toggle() }
            )
            Spacer()
        }
    }

    /// How it plays and how it counts, kept on their own line: the three
    /// mode chips above already fill the width on a narrow phone.
    private var playbackSettings: some View {
        HStack(spacing: 8) {
            SpeedMenuButton(selected: vm.speed, onSelect: vm.setSpeed)
            SubdivisionMenu(selection: subdivision) { picked in
                subdivisionRaw = picked.rawValue
                Task { await refreshClickTrackIfOn() }
            }
            Spacer()
        }
    }

}

// MARK: - Derived state

private extension ListeningPlayerView {

    var hasGrid: Bool {
        clip.hasBeatAnalysis && clip.firstDownbeatSeconds != nil
    }

    var tolerance: Double {
        PhraseGrid.toleranceSeconds(
            bpm: clip.bpm ?? 0,
            fractionOfBeat: exercise.toleranceFraction
        )
    }

    /// Phrase starts, reused for the scrubber's accent ticks so the taller
    /// marks line up with the structure the transport jumps between.
    var phraseIndices: Set<Int> {
        BeatGrid.downbeatIndices(
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            beatsPerMeasure: Self.phraseLength
        )
    }

    var subdivision: CountSubdivision {
        CountSubdivision(rawValue: subdivisionRaw) ?? .quarter
    }

    /// What the counter says right now. On the beat that's its number; in
    /// between it's the subdivision syllable.
    func spokenCount(at time: Double) -> String? {
        guard let beat = countPosition(at: time) else { return nil }
        guard subdivision != .quarter else { return "\(beat)" }
        guard let slot = PhraseGrid.subdivisionIndex(
            currentTime: time,
            beatTimes: clip.beatTimes,
            perBeat: subdivision.perBeat
        ) else { return "\(beat)" }
        return subdivision.spoken(beat: beat, index: slot)
    }

    /// Which slot inside the beat the playhead is in, for the count row.
    func slotIndex(at time: Double) -> Int? {
        guard subdivision != .quarter else { return 0 }
        return PhraseGrid.subdivisionIndex(
            currentTime: time,
            beatTimes: clip.beatTimes,
            perBeat: subdivision.perBeat
        )
    }

    func countPosition(at time: Double) -> Int? {
        PhraseGrid.phrasePosition(
            currentTime: time,
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            phraseLength: Self.countLength
        )
    }

    /// The count hides only for the drills that depend on it being hidden.
    /// Outside a drill the player always shows it — that is the point.
    var counterRevealed: Bool {
        guard drillsShown, run.phase == .running else { return true }
        switch exercise {
        case .findTheOne: return false
        case .tapTheBeat, .phraseCatcher: return true
        case .countItOut: return run.plan.map { vm.currentTime < $0.revealUntil } ?? true
        }
    }

}

// MARK: - Loading and analysis

private extension ListeningPlayerView {

    /// Loads the asset, then analyses it if it has never been analysed.
    /// Deliberately sequential but non-blocking: `load()` returns as soon as
    /// the item is playable, so the user can hit play while the beat grid is
    /// still being computed.
    func prepare() async {
        await vm.load()
        configureBeatPulse()
        guard !clip.hasBeatAnalysis else { return }
        await vm.detectBeats(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
    }

    /// Throws the cached grid away and analyses again.
    ///
    /// Analysis is cached for good on first open, so a clip analysed by an
    /// older detector keeps its old grid forever unless asked. The loop and
    /// any running drill were built on the old grid, so they go too; the
    /// click is re-cut on the new one.
    func redetectBeats() async {
        run.reset()
        vm.clearLoop()
        await vm.redetectBeats(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
        await refreshClickTrackIfOn()
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

// MARK: - Transport, loop, metronome

private extension ListeningPlayerView {

    func seekPhrase(forward: Bool) {
        let target = forward
            ? PhraseGrid.phraseStart(
                after: vm.currentTime,
                beatTimes: clip.beatTimes,
                anchor: clip.firstDownbeatSeconds,
                phraseLength: Self.phraseLength
            )
            : PhraseGrid.phraseStart(
                before: vm.currentTime,
                beatTimes: clip.beatTimes,
                anchor: clip.firstDownbeatSeconds,
                phraseLength: Self.phraseLength
            )
        guard let target else { return }
        vm.seek(to: target)
    }

    func toggleLoopPhrase() {
        guard vm.loopStart == nil else {
            vm.clearLoop()
            return
        }
        guard let bounds = PhraseGrid.currentPhraseBounds(
            at: vm.currentTime,
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            phraseLength: Self.phraseLength
        ) else { return }
        vm.setLoop(start: bounds.start, end: bounds.end)
        vm.seek(to: bounds.start)
    }

    /// Rebuilds the played asset with or without the click mixed in.
    ///
    /// Flipped optimistically so the chip responds immediately, then rolled
    /// back if composing fails — the alternative is a chip that sits inert
    /// for however long the compose takes.
    func toggleMetronome() async {
        let turningOn = !metronomeOn
        metronomeOn = turningOn
        isSwitchingAudio = true
        defer { isSwitchingAudio = false }

        guard turningOn else {
            await vm.rebuildItem()
            MetronomeMixer.discardClickTrack(at: clickTrackURL)
            clickTrackURL = nil
            configureBeatPulse()
            return
        }
        if await !installClickTrack() {
            metronomeOn = false
        }
        configureBeatPulse()
    }

    /// Re-renders the click when the subdivision changes, but only while it
    /// is actually audible — no point rebuilding the asset for a setting the
    /// user can't currently hear.
    func refreshClickTrackIfOn() async {
        guard metronomeOn else { return }
        isSwitchingAudio = true
        defer { isSwitchingAudio = false }
        await installClickTrack()
        configureBeatPulse()
    }

    /// Composes the click at the chosen subdivision.
    ///
    /// The stored grid is left alone — subdivisions are expanded only for
    /// the click, so drills and step timing keep scoring against real beats.
    @discardableResult
    func installClickTrack() async -> Bool {
        let beats = clip.beatTimes
        let perBeat = subdivision.perBeat
        let clicks = PhraseGrid.subdivide(beatTimes: beats, perBeat: perBeat)
        let measureStride = max(1, clip.beatsPerMeasure) * perBeat
        let anchorIndex = BeatGrid.nearestBeatIndex(
            to: clip.firstDownbeatSeconds ?? 0,
            in: clicks
        ) ?? 0

        var downbeats: Set<Int> = []
        var subdivisions: Set<Int> = []
        for index in clicks.indices {
            if perBeat > 1, (index - anchorIndex) % perBeat != 0 {
                subdivisions.insert(index)
            } else if (index - anchorIndex) % measureStride == 0 {
                downbeats.insert(index)
            }
        }

        // Captured out of the transform so the previous file can be
        // released only after the player has actually switched off it.
        let previousURL = clickTrackURL
        var installedURL: URL?
        let ok = await vm.rebuildItem { source in
            let composed = try await MetronomeMixer.composedAsset(
                source: source,
                beatTimes: clicks,
                downbeatIndices: downbeats,
                subdivisionIndices: subdivisions
            )
            installedURL = composed.fileURL
            return composed.asset
        }
        if let installedURL {
            clickTrackURL = installedURL
            MetronomeMixer.discardClickTrack(at: previousURL)
        }
        return ok
    }
}

// MARK: - Anchor correction

private extension ListeningPlayerView {

    func shiftAnchor(by beats: Int) {
        guard let anchor = clip.firstDownbeatSeconds,
              let shifted = PhraseGrid.shiftAnchor(
                  anchor,
                  byBeats: beats,
                  in: clip.beatTimes,
                  keepingPhaseOf: Self.phraseLength
              ) else { return }
        clip.firstDownbeatSeconds = shifted
        try? modelContext.save()
        configureBeatPulse()
        Task { await refreshClickTrackIfOn() }
    }

    func tapOnBeatOne() {
        vm.tapOnBeatOne(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
        Task { await refreshClickTrackIfOn() }
    }
}

// MARK: - Drills

private extension ListeningPlayerView {

    func startDrill() {
        if exercise == .findTheOne {
            startFindTheOne()
        } else {
            startContinuousDrill()
        }
    }

    func startContinuousDrill() {
        let starts = PhraseGrid.phraseStartTimes(
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            phraseLength: exercise.phraseLength(beatsPerMeasure: clip.beatsPerMeasure)
        )
        let shape = DrillShape(
            leadPhrases: exercise == .countItOut ? revealPhrases : 1,
            scoredPhrases: exercise.lengthInPhrases ?? 1,
            toleranceSeconds: tolerance,
            gradesEveryBeat: exercise.gradesEveryBeat
        )
        guard let plan = ListeningDrillPlanner.randomPlan(
            phraseStarts: starts,
            shape: shape,
            duration: vm.duration,
            beatTimes: clip.beatTimes
        ) else {
            run.fail("This clip is too short for a \(exercise.title) take. Try a longer one.")
            return
        }
        run.begin(plan: plan)
        vm.clearLoop()
        vm.seek(to: plan.playbackStart)
        vm.play()
    }

    func startFindTheOne() {
        guard !clip.beatTimes.isEmpty else {
            run.fail("No beat grid on this clip yet.")
            return
        }
        let latest = max(0.01, vm.duration - 6)
        run.beginOpenEnded()
        vm.clearLoop()
        vm.seek(to: Double.random(in: 0...latest))
        vm.play()
    }

    /// Grades the tap the moment it lands — feedback and haptic together —
    /// then records it for the end-of-take score.
    func recordDrillTap() {
        if exercise == .findTheOne {
            answerFindTheOne()
        } else {
            let time = vm.precisePlaybackTime
            let feedback = PhraseGrid.feedback(
                forTap: time,
                targets: run.plan?.targets ?? [],
                toleranceSeconds: tolerance
            )
            run.recordTap(at: time, feedback: feedback)
            DrillHaptics.play(for: feedback)
        }
    }

    func answerFindTheOne() {
        let time = vm.precisePlaybackTime
        vm.pause()
        let result = FindTheOneResult(
            offsetMs: BeatGrid.offsetMs(from: time, toNearestBeatIn: clip.beatTimes) ?? 0,
            measurePosition: BeatGrid.currentMeasurePosition(
                currentTime: time,
                beatTimes: clip.beatTimes,
                anchor: clip.firstDownbeatSeconds,
                beatsPerMeasure: max(1, clip.beatsPerMeasure)
            )
        )
        run.answer(result)
        DrillHaptics.play(for: TapFeedback(offsetMs: result.offsetMs, isHit: result.landedOnOne))
    }
}
