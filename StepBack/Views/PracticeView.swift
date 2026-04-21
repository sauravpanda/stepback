import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct PracticeView: View {

    let clip: DanceClip

    @StateObject private var vm: PracticePlayerViewModel

    init(clip: DanceClip) {
        self.clip = clip
        _vm = StateObject(
            wrappedValue: PracticePlayerViewModel(assetIdentifier: clip.assetIdentifier)
        )
    }

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            content
        }
        .navigationTitle(clip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = vm.loadError {
            loadErrorState(message: error)
        } else if !vm.isReady {
            ProgressView()
                .tint(Theme.Color.accent)
        } else {
            VStack(spacing: 0) {
                PlayerSurface(player: vm.player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color.black)
                controls
            }
        }
    }

    private func loadErrorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.Color.accent)
            Text("Couldn't load this clip")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textPrimary)
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            Scrubber(
                currentTime: vm.currentTime,
                duration: vm.duration,
                onSeek: vm.seek(to:)
            )
            HStack {
                Text(SpeedFormatter.timestamp(vm.currentTime))
                    .font(Theme.Font.timestamp)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Text(SpeedFormatter.timestamp(vm.duration))
                    .font(Theme.Font.timestamp)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            HStack {
                Spacer()
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .background(Theme.Color.accent, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            SpeedPills(selected: vm.speed, onSelect: vm.setSpeed(_:))
        }
        .padding(16)
    }
}

// MARK: - Player surface

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("PlayerView.layer must be an AVPlayerLayer")
        }
        return layer
    }
}

// MARK: - Scrubber

private struct Scrubber: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @GestureState private var dragProgress: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let progress = dragProgress ?? (duration > 0 ? min(1, currentTime / duration) : 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Color.surfaceElevated)
                    .frame(height: 6)
                Capsule()
                    .fill(Theme.Color.accent)
                    .frame(width: width * progress, height: 6)
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 16, height: 16)
                    .offset(x: max(0, width * progress - 8))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragProgress) { value, state, _ in
                        state = min(1, max(0, value.location.x / width))
                    }
                    .onEnded { value in
                        let ratio = min(1, max(0, value.location.x / width))
                        if duration > 0 {
                            onSeek(ratio * duration)
                        }
                    }
            )
        }
        .frame(height: 32)
    }
}

// MARK: - Speed pills

private struct SpeedPills: View {
    static let speeds: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5]
    let selected: Double
    let onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.speeds, id: \.self) { speed in
                let isSelected = SpeedFormatter.equals(selected, speed)
                let tint = Theme.Color.speedPillColor(for: speed)
                Button {
                    onSelect(speed)
                } label: {
                    Text(SpeedFormatter.pill(speed))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? tint : Theme.Color.surfaceElevated)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Formatting

enum SpeedFormatter {
    static func pill(_ speed: Double) -> String {
        let base: String
        if speed == speed.rounded() {
            base = "\(Int(speed))"
        } else {
            base = String(format: "%g", speed)
        }
        return "\(base)×"
    }

    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let totalCentis = Int((seconds * 100).rounded())
        let mins = totalCentis / 6000
        let secs = (totalCentis / 100) % 60
        let cent = totalCentis % 100
        return String(format: "%d:%02d.%02d", mins, secs, cent)
    }

    static func equals(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.001
    }
}
