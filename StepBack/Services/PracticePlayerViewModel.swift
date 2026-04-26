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

    @Published var mirrored: Bool = false

    @Published private(set) var isAnalyzingBeats: Bool = false
    @Published var analysisError: String?

    @Published var stepTimingActive: Bool = false
    @Published private(set) var stepTaps: [StepTap] = []

    let player: AVPlayer

    // `timeObserver` is written once in init and read once in deinit — both
    // outside the normal actor-isolated execution path — so it is marked
    // nonisolated(unsafe) rather than dragged through MainActor.
    private nonisolated(unsafe) var timeObserver: Any?
    private var playerItem: AVPlayerItem?

    private let assetIdentifier: String
    private var localFileURL: URL?
    private let photosService: PhotosServicing

    init(
        assetIdentifier: String,
        localFileURL: URL? = nil,
        photosService: PhotosServicing = PhotosService(),
        player: AVPlayer = AVPlayer()
    ) {
        self.assetIdentifier = assetIdentifier
        self.localFileURL = localFileURL
        self.photosService = photosService
        self.player = player
        attachTimeObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
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
                urlAsset = try await photosService.resolveAVAsset(for: assetIdentifier)
            }
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

    // MARK: - Transport

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        player.playImmediately(atRate: Float(speed))
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
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

    // MARK: - Mirror

    func toggleMirror() {
        mirrored.toggle()
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
            isAnalyzingBeats = false
            onSave()
        } catch {
            isAnalyzingBeats = false
            analysisError = error.localizedDescription
        }
    }

    /// Marks `currentTime` as beat 1. Caller persists.
    func tapOnBeatOne(for clip: DanceClip, onSave: @escaping () -> Void) {
        clip.firstDownbeatSeconds = currentTime
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
        guard let offset = BeatGrid.offsetMs(
            from: currentTime,
            toNearestBeatIn: beatTimes
        ) else { return }
        stepTaps.append(StepTap(time: currentTime, offsetMs: offset))
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

    func applyMarker(_ marker: LoopMarker) {
        loopStart = marker.startSeconds
        loopEnd = marker.endSeconds
        setSpeed(marker.preferredSpeed)
        seek(to: marker.startSeconds)
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
