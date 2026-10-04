import AVFoundation
import SwiftUI
import UIKit

/// The single `AVPlayerLayer` host used by every video surface (practice,
/// trim). Previously this was copy-pasted per view, and only the practice
/// copy carried the background detach/reattach logic — so other surfaces'
/// playback would die when the app backgrounded. One surface, one behaviour.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerSurfaceView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("PlayerSurfaceView.layer must be an AVPlayerLayer")
        }
        return layer
    }

    // Detach the AVPlayer from the layer when backgrounding so iOS keeps
    // audio flowing even with the Background Audio capability enabled. While
    // a video output is attached, the system aggressively pauses the player;
    // nil-ing it lets the audio session keep going. Reattach on foreground so
    // the user sees frames again.
    private var stashedPlayer: AVPlayer?
    /// Tokens for the background/foreground observers. Held so they can be
    /// removed individually when the view leaves its window.
    private var lifecycleObservers: [NSObjectProtocol] = []

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Always clear first so re-parenting (didMoveToWindow can fire more
        // than once) never stacks duplicate observers.
        removeLifecycleObservers()
        guard window != nil else { return }
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.detachForBackground() }
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reattachForForeground() }
            }
        ]
    }

    private func removeLifecycleObservers() {
        for token in lifecycleObservers {
            NotificationCenter.default.removeObserver(token)
        }
        lifecycleObservers = []
    }

    private func detachForBackground() {
        stashedPlayer = playerLayer.player
        playerLayer.player = nil
    }

    private func reattachForForeground() {
        if let stashedPlayer {
            playerLayer.player = stashedPlayer
        }
        stashedPlayer = nil
    }

    deinit {
        for token in lifecycleObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
