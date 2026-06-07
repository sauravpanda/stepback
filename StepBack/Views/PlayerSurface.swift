import AVFoundation
import SwiftUI
import UIKit

/// The single `AVPlayerLayer` host used by every video surface (practice,
/// compare, trim). Previously this was copy-pasted into three views, and
/// only the practice copy carried the background detach/reattach logic — so
/// compare/trim playback would die when the app backgrounded. One surface,
/// one behaviour.
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Always clear first so re-parenting (didMoveToWindow can fire more
        // than once) never stacks duplicate observers.
        NotificationCenter.default.removeObserver(self)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(detachForBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reattachForForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func detachForBackground() {
        stashedPlayer = playerLayer.player
        playerLayer.player = nil
    }

    @objc private func reattachForForeground() {
        if let stashedPlayer {
            playerLayer.player = stashedPlayer
        }
        stashedPlayer = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
