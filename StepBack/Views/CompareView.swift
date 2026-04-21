import AVFoundation
import SwiftData
import SwiftUI
import UIKit

struct CompareView: View {

    let primaryClip: DanceClip
    let secondaryClip: DanceClip

    @StateObject private var primary: PracticePlayerViewModel
    @StateObject private var secondary: PracticePlayerViewModel

    @State private var speed: Double = 1.0
    @State private var primaryMirrored: Bool = false
    @State private var secondaryMirrored: Bool = false

    init(primary: DanceClip, secondary: DanceClip) {
        self.primaryClip = primary
        self.secondaryClip = secondary
        _primary = StateObject(
            wrappedValue: PracticePlayerViewModel(assetIdentifier: primary.assetIdentifier)
        )
        _secondary = StateObject(
            wrappedValue: PracticePlayerViewModel(assetIdentifier: secondary.assetIdentifier)
        )
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                Theme.Color.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    if isLandscape {
                        HStack(spacing: 12) {
                            panel(for: primary, clip: primaryClip, mirrored: $primaryMirrored)
                            panel(for: secondary, clip: secondaryClip, mirrored: $secondaryMirrored)
                        }
                    } else {
                        VStack(spacing: 12) {
                            panel(for: primary, clip: primaryClip, mirrored: $primaryMirrored)
                            panel(for: secondary, clip: secondaryClip, mirrored: $secondaryMirrored)
                        }
                    }
                    sharedControls
                }
                .padding(12)
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            async let left: () = primary.load()
            async let right: () = secondary.load()
            _ = await (left, right)
            secondary.setMuted(true)
        }
        .onDisappear {
            primary.pause()
            secondary.pause()
        }
    }

    // MARK: - Panels

    private func panel(
        for viewModel: PracticePlayerViewModel,
        clip: DanceClip,
        mirrored: Binding<Bool>
    ) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ComparePlayerSurface(player: viewModel.player)
                    .scaleEffect(x: mirrored.wrappedValue ? -1 : 1, y: 1)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                    mirrored.wrappedValue.toggle()
                } label: {
                    Image(systemName: mirrored.wrappedValue
                        ? "rectangle.portrait.on.rectangle.portrait.angled.fill"
                        : "rectangle.portrait.on.rectangle.portrait.angled"
                    )
                    .foregroundStyle(mirrored.wrappedValue ? Theme.Color.accent : .white)
                    .padding(8)
                    .background(Color.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(mirrored.wrappedValue ? "Unmirror" : "Mirror")
            }
            HStack {
                Text(clip.title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(SpeedFormatter.timestamp(viewModel.currentTime))
                    .font(Theme.Font.timestamp)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - Shared controls

    private var sharedControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 32) {
                Spacer()
                Button {
                    primary.restart()
                    secondary.restart()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Button {
                    togglePlayPauseBoth()
                } label: {
                    Image(systemName: anyPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .background(Theme.Color.accent, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            SpeedPills(selected: speed, onSelect: setSpeed)
        }
    }

    private var anyPlaying: Bool { primary.isPlaying || secondary.isPlaying }

    private func togglePlayPauseBoth() {
        if anyPlaying {
            primary.pause()
            secondary.pause()
        } else {
            primary.setSpeed(speed)
            secondary.setSpeed(speed)
            primary.play()
            secondary.play()
        }
    }

    private func setSpeed(_ newSpeed: Double) {
        speed = newSpeed
        primary.setSpeed(newSpeed)
        secondary.setSpeed(newSpeed)
    }
}

// MARK: - Internal player surface (duplicated to keep PracticeView's private)

private struct ComparePlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> CompareLayerView {
        let view = CompareLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: CompareLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class CompareLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("CompareLayerView.layer must be an AVPlayerLayer")
        }
        return layer
    }
}

// MARK: - Picker sheet

struct CompareClipPicker: View {
    let excludedID: UUID
    let onPick: (DanceClip) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DanceClip.dateAdded, order: .reverse) private var clips: [DanceClip]

    var body: some View {
        NavigationStack {
            List {
                ForEach(clips.filter { $0.id != excludedID }) { clip in
                    Button {
                        onPick(clip)
                        dismiss()
                    } label: {
                        HStack {
                            thumbnail(for: clip)
                                .frame(width: 56, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) {
                                Text(clip.title)
                                    .font(Theme.Font.bodyEmphasized)
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Text(clip.dateAdded, style: .date)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Pick a clip to compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func thumbnail(for clip: DanceClip) -> some View {
        if let data = clip.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            ZStack {
                Theme.Color.surfaceElevated
                Image(systemName: "film")
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }
}
