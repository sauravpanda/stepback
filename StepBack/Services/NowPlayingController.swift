import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Bridges an `AVPlayer` to `MPNowPlayingInfoCenter` and the
/// `MPRemoteCommandCenter`. Surfaces title + artwork + transport state on
/// the lock screen and Control Center, and routes Play/Pause/Skip commands
/// from there back to the player.
///
/// Owned by `PracticePlayerViewModel`; `activate()` should be called when
/// PracticeView appears, `deactivate()` when it disappears.
@MainActor
final class NowPlayingController {

    private let player: AVPlayer
    private weak var clip: DanceClip?
    private var commandHandlers: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var rateObservation: NSKeyValueObservation?

    init(player: AVPlayer, clip: DanceClip) {
        self.player = player
        self.clip = clip
    }

    func activate() {
        registerCommands()
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateInfo() }
        }
        updateInfo()
    }

    func deactivate() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        commandHandlers.removeAll()
        rateObservation?.invalidate()
        rateObservation = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Push the latest state (title, position, rate) to Now Playing.
    /// Called whenever transport state changes meaningfully.
    func updateInfo() {
        guard let clip else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = clip.title
        info[MPMediaItemPropertyArtist] = clip.eventName ?? "StepBack"
        if let duration = player.currentItem?.duration.seconds, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        let elapsed = player.currentTime().seconds
        if elapsed.isFinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)

        if let data = clip.thumbnailData, let image = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote commands

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [1]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [1]
        center.changePlaybackPositionCommand.isEnabled = true

        commandHandlers.append(center.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            self?.updateInfo()
            return .success
        })
        commandHandlers.append(center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            self?.updateInfo()
            return .success
        })
        commandHandlers.append(center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if player.rate > 0 { player.pause() } else { player.play() }
            updateInfo()
            return .success
        })
        commandHandlers.append(center.skipForwardCommand.addTarget { [weak self] _ in
            self?.player.currentItem?.step(byCount: 1)
            self?.updateInfo()
            return .success
        })
        commandHandlers.append(center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.player.currentItem?.step(byCount: -1)
            self?.updateInfo()
            return .success
        })
        commandHandlers.append(center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let target = CMTime(seconds: positionEvent.positionTime, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            updateInfo()
            return .success
        })
    }
}
