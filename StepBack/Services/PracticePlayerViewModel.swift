import AVFoundation
import Combine
import Foundation

@MainActor
final class PracticePlayerViewModel: ObservableObject {

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var speed: Double = 1.0
    @Published private(set) var isReady: Bool = false
    @Published var loadError: String?

    @Published private(set) var loopStart: Double?
    @Published private(set) var loopEnd: Double?

    /// Quarter-turns (90° clockwise each, 0…3) applied to the displayed
    /// video. Display-only — the underlying asset and pose detection are
    /// untouched; the view rotates the surface and un-rotates touches.
    @Published private(set) var rotationQuarterTurns: Int = 0

    @Published private(set) var isAnalyzingBeats: Bool = false
    @Published var analysisError: String?

    @Published var stepTimingActive: Bool = false
    @Published private(set) var stepTaps: [StepTap] = []

    let player: AVPlayer

    // `timeObserver` is written once in init and read once in deinit — both
    // outside the normal actor-isolated execution path — so it is marked
    // nonisolated(unsafe) rather than dragged through MainActor.
    private nonisolated(unsafe) var timeObserver: Any?
    private nonisolated(unsafe) var beatBoundaryObserver: Any?
    private nonisolated(unsafe) var endOfItemObserver: NSObjectProtocol?
    private var configuredBeatTimes: [Double] = []
    private var configuredDownbeatIndices: Set<Int> = []
    private var playerItem: AVPlayerItem?
    /// The resolved source, kept so the played item can be rebuilt — e.g.
    /// re-composed with a metronome click — without resolving the Photos
    /// asset a second time. See `rebuildItem(transform:)`.
    private var sourceAsset: AVURLAsset?

    /// Increments every time the player crosses a beat boundary. UI binds to
    /// this rather than `currentTime` so the pulse animation only re-renders
    /// on beat transitions, not on every periodic time observer tick.
    @Published private(set) var beatPulseID: Int = 0
    /// Whether the most recent beat boundary was a downbeat (count 1). UI
    /// uses this to scale the pulse bigger on the first beat of a measure.
    @Published private(set) var lastBeatWasDownbeat: Bool = false

    private var assetIdentifier: String
    private let cloudIdentifier: String?
    private var localFileURL: URL?
    private let photosService: PhotosServicing
    private var nowPlaying: NowPlayingController?
    /// Fired when a stale local Photos identifier was healed through the
    /// cloud identifier, so the owner can persist the fresh one on the clip.
    private let onLocalIdentifierRemapped: ((String) -> Void)?

    init(
        assetIdentifier: String,
        cloudIdentifier: String? = nil,
        localFileURL: URL? = nil,
        photosService: PhotosServicing = PhotosService(),
        player: AVPlayer = AVPlayer(),
        onLocalIdentifierRemapped: ((String) -> Void)? = nil
    ) {
        self.assetIdentifier = assetIdentifier
        self.cloudIdentifier = cloudIdentifier
        self.localFileURL = localFileURL
        self.photosService = photosService
        self.player = player
        self.onLocalIdentifierRemapped = onLocalIdentifierRemapped
        attachTimeObserver()
        attachEndOfItemObserver()
    }

    deinit {
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let beatBoundaryObserver {
            player.removeTimeObserver(beatBoundaryObserver)
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        player.playImmediately(atRate: Float(speed))
        isPlaying = true
        nowPlaying?.updateInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        nowPlaying?.updateInfo()
    }

    func restart() {
        seek(to: 0)
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        nowPlaying?.updateInfo()
    }

    func setSpeed(_ newSpeed: Double) {
        speed = newSpeed
        if isPlaying {
            player.rate = Float(newSpeed)
        }
    }

    // MARK: - Frame stepping

    func stepForward() { step(by: 1) }
    func stepBackward() { step(by: -1) }

    private func step(by count: Int) {
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        player.currentItem?.step(byCount: count)
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            currentTime = max(0, min(seconds, duration))
        }
    }

    // MARK: - Rotation

    /// Advances the display rotation by 90° clockwise, wrapping back to
    /// upright after four taps.
    func rotate() {
        rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
    }

    // MARK: - Beat detection

    /// Runs `BeatDetector` against the currently-loaded asset and writes the
    /// result back into `clip`. The caller is responsible for persisting the
    /// model context via `onSave`.
    func detectBeats(for clip: DanceClip, onSave: @escaping () -> Void) async {
        guard !isAnalyzingBeats, !clip.hasBeatAnalysis else { return }
        guard let asset = player.currentItem?.asset else {
            analysisError = "Clip hasn't finished loading yet."
            return
        }
        isAnalyzingBeats = true
        analysisError = nil
        do {
            let analysis = try await BeatDetector.analyze(asset: asset)
            clip.bpm = analysis.bpm
            clip.setBeatTimes(analysis.beatTimes)
            // Seed the anchor from the detector's guess so the count starts
            // on its own. Only when there isn't one already — a downbeat the
            // user placed by hand always outranks the estimate.
            if clip.firstDownbeatSeconds == nil {
                clip.firstDownbeatSeconds = analysis.downbeatSeconds
            }
            isAnalyzingBeats = false
            onSave()
        } catch {
            isAnalyzingBeats = false
            analysisError = error.localizedDescription
        }
    }

    /// Marks the current playback position as beat 1. Caller persists.
    ///
    /// Reads `precisePlaybackTime` rather than `currentTime`: every measure
    /// counter, downbeat pulse and phrase grid in the app is derived from
    /// this one value, so quantisation error here shifts everything
    /// downstream.
    func tapOnBeatOne(for clip: DanceClip, onSave: @escaping () -> Void) {
        clip.firstDownbeatSeconds = precisePlaybackTime
        onSave()
    }

    func clearDownbeatAnchor(for clip: DanceClip, onSave: @escaping () -> Void) {
        clip.firstDownbeatSeconds = nil
        onSave()
    }

    // MARK: - Step timing

    func toggleStepTiming() {
        stepTimingActive.toggle()
        if !stepTimingActive {
            stepTaps.removeAll()
        }
    }

    func recordStepTap(against beatTimes: [Double]) {
        guard stepTimingActive, !beatTimes.isEmpty else { return }
        let tapTime = precisePlaybackTime
        guard let offset = BeatGrid.offsetMs(
            from: tapTime,
            toNearestBeatIn: beatTimes
        ) else { return }
        stepTaps.append(StepTap(time: tapTime, offsetMs: offset))
    }

    func clearStepTaps() {
        stepTaps.removeAll()
    }

    /// Rescales the cached beat grid by `factor` (2 or 0.5), updates the BPM,
    /// and snaps any existing downbeat anchor to the nearest beat on the new
    /// grid so the measure counter doesn't drift.
    func rescaleBeats(for clip: DanceClip, factor: Double, onSave: @escaping () -> Void) {
        guard clip.hasBeatAnalysis, factor > 0 else { return }
        let rescaled = BeatGrid.rescale(beatTimes: clip.beatTimes, factor: factor)
        clip.setBeatTimes(rescaled)
        if let bpm = clip.bpm {
            clip.bpm = bpm * factor
        }
        if let anchor = clip.firstDownbeatSeconds,
           let snapped = BeatGrid.nearestBeatIndex(to: anchor, in: rescaled) {
            clip.firstDownbeatSeconds = rescaled[snapped]
        }
        onSave()
    }

    // MARK: - A/B loop

    var hasLoopRegion: Bool {
        guard let start = loopStart, let end = loopEnd else { return false }
        return end > start
    }

    func markLoopStart() {
        loopStart = currentTime
        if let end = loopEnd, end <= currentTime {
            loopEnd = nil
        }
        activeSegmentID = nil
    }

    func markLoopEnd() {
        if let start = loopStart, currentTime <= start {
            // Ignore: an end-before-start marker would be invalid.
            return
        }
        loopEnd = currentTime
        activeSegmentID = nil
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
        activeSegmentID = nil
    }

    // MARK: - Segments

    @Published private(set) var activeSegmentID: UUID?

    /// Plays a segment by clamping the loop region to its bounds and starting
    /// playback at its start. Reuses the same loop machinery as A/B so the
    /// existing `LoopEvaluator` keeps it bounded automatically.
    func playSegment(_ segment: ClipSegment) {
        activeSegmentID = segment.id
        loopStart = segment.startSeconds
        loopEnd = segment.endSeconds
        setSpeed(segment.preferredSpeed)
        seek(to: segment.startSeconds)
        play()
    }

    func clearActiveSegment() {
        activeSegmentID = nil
        clearLoop()
    }

    // MARK: - Observers

    private func attachTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            // queue: .main guarantees we are on the main thread here.
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                    if case .seek(let target) = LoopEvaluator.action(
                        currentTime: seconds,
                        loopStart: self.loopStart,
                        loopEnd: self.loopEnd
                    ) {
                        self.seek(to: target)
                    }
                }
                self.isPlaying = self.player.rate > 0
            }
        }
    }
}

// MARK: - Pure loop logic (testable without AVPlayer)

enum LoopEvaluator {
    enum Action: Equatable {
        case none
        case seek(to: Double)
    }

    static func action(
        currentTime: Double,
        loopStart: Double?,
        loopEnd: Double?
    ) -> Action {
        guard let start = loopStart, let end = loopEnd, end > start else {
            return .none
        }
        if currentTime >= end {
            return .seek(to: start)
        }
        return .none
    }
}

// MARK: - Precise timing

extension PracticePlayerViewModel {

    /// Transport position read straight from the player, for grading taps.
    ///
    /// `currentTime` is only refreshed by the 0.1s periodic observer, which
    /// is the right cadence for driving UI but leaves it up to 100ms stale
    /// — far too coarse to score against, when `StepRating` calls anything
    /// under 50ms "perfect". Falls back to the published value when the
    /// player reports a non-finite time (nothing loaded yet).
    ///
    /// Declared out of line only to avoid growing a class body that is
    /// already over SwiftLint's `type_body_length` limit.
    var precisePlaybackTime: Double {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return currentTime }
        return max(0, min(seconds, duration))
    }
}

// MARK: - Item rebuilding and direct loop control

extension PracticePlayerViewModel {

    /// Rebuilds the played item from the already-resolved source, optionally
    /// transforming it first, and restores position and play state.
    ///
    /// The Listen tab uses this to fold a metronome click into the audio.
    /// Going back through `load()` would re-resolve the Photos asset and
    /// drop the user's place in the track; this keeps both.
    /// Returns whether the swap succeeded.
    ///
    /// Callers need the outcome of *this* call, not the state of
    /// `loadError`: that field is sticky, so a caller inferring failure from
    /// it would keep rolling back forever after one unrelated hiccup. A
    /// successful rebuild also clears it, because a stale message describing
    /// a load that has since been superseded is just noise on screen.
    @discardableResult
    func rebuildItem(
        transform: ((AVURLAsset) async throws -> AVAsset)? = nil
    ) async -> Bool {
        guard let sourceAsset else { return false }
        let resumeAt = precisePlaybackTime
        let wasPlaying = isPlaying
        pause()
        do {
            let playable: AVAsset = try await transform?(sourceAsset) ?? sourceAsset
            let item = AVPlayerItem(asset: playable)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            playerItem = item
            seek(to: resumeAt)
            if wasPlaying {
                play()
            }
            loadError = nil
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    /// Sets both loop markers at once.
    ///
    /// `markLoopStart` / `markLoopEnd` read the playhead, which is right for
    /// the Practice tab's hand-placed A/B loops but wrong for looping a
    /// phrase, where both bounds come from the beat grid rather than from
    /// where the user happened to be.
    func setLoop(start: Double, end: Double) {
        guard end > start else { return }
        loopStart = start
        loopEnd = end
        activeSegmentID = nil
    }
}

// MARK: - Beat pulse, Now Playing, loading

/// Moved out of the class body to bring it back under SwiftLint's
/// `type_body_length` limit, which it had already exceeded. These are
/// ordinary members — `private` is file-scoped, so they still reach the
/// stored properties above.
extension PracticePlayerViewModel {

    // MARK: - Beat pulse

    /// Registers boundary-time observers at every entry in `beatTimes`.
    /// AVPlayer fires the callback when playback crosses each timestamp,
    /// which is more accurate (and cheaper) than checking against
    /// `currentTime` from the periodic observer. Idempotent — calling again
    /// tears down the previous observer first, so it's safe to invoke when
    /// beats are re-detected.
    func configureBeatPulse(beatTimes: [Double], downbeatIndices: Set<Int>) {
        if let beatBoundaryObserver {
            player.removeTimeObserver(beatBoundaryObserver)
            self.beatBoundaryObserver = nil
        }
        configuredBeatTimes = beatTimes
        configuredDownbeatIndices = downbeatIndices
        guard !beatTimes.isEmpty else { return }

        let nsValues = beatTimes.map {
            NSValue(time: CMTime(seconds: $0, preferredTimescale: 600))
        }
        beatBoundaryObserver = player.addBoundaryTimeObserver(
            forTimes: nsValues,
            queue: .main
        ) { [weak self] in
            // queue: .main → safe to assume MainActor.
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = self.player.currentTime().seconds
                // The boundary that fired is the latest beat time at or
                // before `now` (with a small slack for timer jitter).
                let index = self.configuredBeatTimes.lastIndex { $0 <= now + 0.05 }
                    ?? 0
                self.lastBeatWasDownbeat = self.configuredDownbeatIndices.contains(index)
                self.beatPulseID &+= 1
            }
        }
    }

    // MARK: - Now Playing

    func enableNowPlaying(for clip: DanceClip) {
        let controller = NowPlayingController(player: player, clip: clip)
        controller.activate()
        nowPlaying = controller
    }

    func disableNowPlaying() {
        nowPlaying?.deactivate()
        nowPlaying = nil
    }

    // MARK: - Loading

    /// Swaps the underlying source (e.g. after a trim writes a new file) and
    /// reloads. Resets transport state so the user doesn't end up paused at
    /// a timestamp that no longer exists in the new timeline.
    func reloadAsset(localFileURL: URL?) async {
        self.localFileURL = localFileURL
        pause()
        loopStart = nil
        loopEnd = nil
        activeSegmentID = nil
        currentTime = 0
        duration = 0
        isReady = false
        loadError = nil
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        await load()
    }

    func load() async {
        guard !isReady else { return }
        do {
            let urlAsset: AVURLAsset
            if let localFileURL {
                urlAsset = AVURLAsset(url: localFileURL)
            } else {
                let resolved = try await photosService.resolveAVAsset(
                    localIdentifier: assetIdentifier,
                    cloudIdentifier: cloudIdentifier
                )
                urlAsset = resolved.asset
                if let healed = resolved.remappedLocalIdentifier {
                    assetIdentifier = healed
                    onLocalIdentifierRemapped?(healed)
                }
            }
            sourceAsset = urlAsset
            let loadedDuration = try await urlAsset.load(.duration).seconds
            let item = AVPlayerItem(asset: urlAsset)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            playerItem = item
            duration = loadedDuration.isFinite ? loadedDuration : 0
            isReady = true
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - End of playback

private extension PracticePlayerViewModel {

    /// Clears `isPlaying` when the item runs out.
    ///
    /// AVPlayer stops at the end but publishes nothing this class was
    /// listening for, so the transport went on showing a pause button over a
    /// stopped player. Observed with a nil object and filtered by identity so
    /// the subscription survives `replaceCurrentItem` — the Listen tab swaps
    /// the item whenever the metronome is toggled.
    func attachEndOfItemObserver() {
        endOfItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // queue: .main → safe to assume MainActor.
            MainActor.assumeIsolated {
                guard let self,
                      let finished = note.object as? AVPlayerItem,
                      finished === self.player.currentItem else { return }
                self.isPlaying = false
                self.nowPlaying?.updateInfo()
            }
        }
    }
}
