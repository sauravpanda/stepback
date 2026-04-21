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
            }
            self.isPlaying = self.player.rate > 0
        }
    }
}
