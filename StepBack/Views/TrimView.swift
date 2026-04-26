import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import UIKit

/// Modal trim editor. Shares the parent practice screen's `AVPlayer` so we
/// don't double the in-memory video buffers — long clips on a phone will
/// blow past the per-process limit fast if two players are decoding the
/// same source.
///
/// Picks a [start, end] window with two handles, then exports the range
/// to the sandbox and rebases all annotations on the new timeline.
struct TrimView: View {

    let clip: DanceClip
    let player: AVPlayer
    let initialDuration: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var duration: Double
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var timeObserver: Any?

    init(clip: DanceClip, player: AVPlayer, initialDuration: Double) {
        self.clip = clip
        self.player = player
        self.initialDuration = initialDuration
        _duration = State(initialValue: initialDuration)
        _trimEnd = State(initialValue: initialDuration)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Color.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Trim clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task { await applyTrim() }
                    }
                    .disabled(!canApply || isExporting)
                }
            }
        }
        .onAppear {
            seek(to: 0)
            attachTimeObserver()
        }
        .onDisappear { detachTimeObserver() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 16) {
            videoPanel
            handles
            preset
            if let exportError {
                Text(exportError)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            if isExporting {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.Color.accent)
                    Text("Exporting…")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var videoPanel: some View {
        TrimPlayerSurface(player: player)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)
            .overlay(alignment: .bottom) {
                HStack {
                    Button {
                        togglePlayPause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Theme.Color.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(SpeedFormatter.timestamp(currentTime)) / \(SpeedFormatter.timestamp(duration))")
                        .font(Theme.Font.timestamp)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.4), in: Capsule())
                }
                .padding(8)
            }
    }

    private var handles: some View {
        VStack(spacing: 10) {
            TrimRangeBar(
                duration: max(duration, 0.001),
                currentTime: currentTime,
                trimStart: $trimStart,
                trimEnd: $trimEnd,
                onSeek: { seek(to: $0) }
            )
            HStack {
                rangeChip(
                    label: "Start",
                    value: trimStart,
                    set: {
                        trimStart = currentTime
                        if trimEnd <= trimStart + 0.05 {
                            trimEnd = min(duration, trimStart + 0.5)
                        }
                    }
                )
                Spacer()
                Text(SpeedFormatter.timestamp(max(0, trimEnd - trimStart)))
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Spacer()
                rangeChip(
                    label: "End",
                    value: trimEnd,
                    set: {
                        trimEnd = currentTime
                        if trimStart >= trimEnd - 0.05 {
                            trimStart = max(0, trimEnd - 0.5)
                        }
                    }
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, 8)
    }

    private var preset: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heads up")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
            Text("Trimming replaces the clip's source with a new file. Patterns and beat times are kept and shifted to the new timeline; anything outside the kept window is dropped.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func rangeChip(label: String, value: Double, set: @escaping () -> Void) -> some View {
        Button(action: set) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(SpeedFormatter.timestamp(value))
                    .font(Theme.Font.timestamp)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transport

    private func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    private func attachTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            currentTime = max(0, min(seconds, duration))
            isPlaying = player.rate > 0
            if seconds >= trimEnd, duration > 0 {
                player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    private func detachTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player.pause()
    }

    // MARK: - Apply

    private var canApply: Bool {
        duration > 0
            && trimEnd - trimStart > 0.05
            && (trimStart > 0.05 || trimEnd < duration - 0.05)
    }

    private func applyTrim() async {
        guard let asset = player.currentItem?.asset else {
            exportError = "Clip isn't ready yet."
            return
        }
        player.pause()
        isPlaying = false
        isExporting = true
        exportError = nil
        do {
            let result = try await TrimExportService().export(
                asset: asset,
                start: trimStart,
                end: trimEnd
            )
            applyToModel(fileName: result.fileName, newDuration: result.durationSeconds)
            isExporting = false
            dismiss()
        } catch {
            isExporting = false
            exportError = error.localizedDescription
        }
    }

    private func applyToModel(fileName: String, newDuration: Double) {
        if let previous = clip.trimmedFileName {
            TrimStorage.deleteIfExists(name: previous)
        }
        clip.trimmedFileName = fileName
        clip.durationSeconds = newDuration

        let start = trimStart
        let end = trimEnd
        clip.firstDownbeatSeconds = clip.firstDownbeatSeconds.flatMap {
            TrimAnnotationShifter.shiftPoint($0, trimStart: start, trimEnd: end)
        }
        clip.setBeatTimes(
            TrimAnnotationShifter.shiftBeatTimes(clip.beatTimes, trimStart: start, trimEnd: end)
        )

        for segment in clip.segments {
            if let shifted = TrimAnnotationShifter.shiftRange(
                start: segment.startSeconds,
                end: segment.endSeconds,
                trimStart: start,
                trimEnd: end
            ) {
                segment.startSeconds = shifted.start
                segment.endSeconds = shifted.end
            } else {
                modelContext.delete(segment)
            }
        }

        try? modelContext.save()
    }
}

// MARK: - Player surface

private struct TrimPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TrimPlayerView {
        let view = TrimPlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: TrimPlayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class TrimPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("TrimPlayerView.layer must be an AVPlayerLayer")
        }
        return layer
    }
}

// MARK: - Range bar

/// Two draggable handles + a playhead. The playhead is read-only here —
/// dragging the bar (not a handle) seeks the preview player.
private struct TrimRangeBar: View {

    let duration: Double
    let currentTime: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let onSeek: (Double) -> Void

    @GestureState private var dragOffset: CGFloat = 0
    private let handleWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let startX = xFor(time: trimStart, width: width)
            let endX = xFor(time: trimEnd, width: width)
            let playX = xFor(time: currentTime, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Color.surfaceElevated)
                    .frame(height: 8)

                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: max(0, startX), height: 30)
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: max(0, width - endX), height: 30)
                    .offset(x: endX)

                Capsule()
                    .fill(Theme.Color.accentSoft)
                    .frame(width: max(2, endX - startX), height: 12)
                    .offset(x: startX)

                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: 28)
                    .offset(x: max(0, playX - 1))

                handleView()
                    .offset(x: max(0, startX - handleWidth / 2))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let t = timeFor(x: value.location.x, width: width)
                                trimStart = max(0, min(t, trimEnd - 0.05))
                                onSeek(trimStart)
                            }
                    )

                handleView()
                    .offset(x: max(0, endX - handleWidth / 2))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let t = timeFor(x: value.location.x, width: width)
                                trimEnd = min(duration, max(t, trimStart + 0.05))
                                onSeek(trimEnd)
                            }
                    )
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
    }

    private func xFor(time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, time / duration))) * width
    }

    private func timeFor(x: CGFloat, width: CGFloat) -> Double {
        let ratio = Double(min(width, max(0, x)) / width)
        return ratio * duration
    }

    private func handleView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.Color.accent)
                .frame(width: handleWidth, height: 30)
            RoundedRectangle(cornerRadius: 1)
                .fill(.black.opacity(0.4))
                .frame(width: 2, height: 14)
        }
    }
}
