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

    let player: AVPlayer
    private var timeObserver: Any?
    private var playerItem: AVPlayerItem?

    private let assetIdentifier: String
    private let photosService: PhotosServicing

    init(
        assetIdentifier: String,
        photosService: PhotosServicing = PhotosService(),
        player: AVPlayer = AVPlayer()
    ) {
        self.assetIdentifier = assetIdentifier
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

    func load() async {
        guard !isReady else { return }
        do {
            let urlAsset = try await photosService.resolveAVAsset(for: assetIdentifier)
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
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: Float(speed))
            isPlaying = true
        }
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
    }

    func markLoopEnd() {
        if let start = loopStart, currentTime <= start {
            // Ignore: an end-before-start marker would be invalid.
            return
        }
        loopEnd = currentTime
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
    }

    func applyMarker(_ marker: LoopMarker) {
        loopStart = marker.startSeconds
        loopEnd = marker.endSeconds
        setSpeed(marker.preferredSpeed)
        seek(to: marker.startSeconds)
    }

    // MARK: - Observers

    private func attachTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
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
