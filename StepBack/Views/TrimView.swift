import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import UIKit

/// Modal trim editor. Plays the clip muted in a loop within the chosen
/// [start, end] window so the user can audition the trim, then exports
/// the range to the sandbox and rebases all annotations on the new
/// timeline.
struct TrimView: View {

    let clip: DanceClip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var preview: PracticePlayerViewModel
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var hasInitializedHandles = false

    init(clip: DanceClip) {
        self.clip = clip
        _preview = StateObject(
            wrappedValue: PracticePlayerViewModel(
                assetIdentifier: clip.assetIdentifier,
                localFileURL: clip.trimmedFileURL
            )
        )
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
        .task { await preview.load() }
        .onChange(of: preview.duration) { _, newDuration in
            if !hasInitializedHandles, newDuration > 0 {
                trimStart = 0
                trimEnd = newDuration
                hasInitializedHandles = true
                preview.seek(to: 0)
            }
        }
        .onChange(of: preview.currentTime) { _, t in
            // Loop preview within the chosen window.
            if t >= trimEnd, preview.duration > 0 {
                preview.seek(to: trimStart)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = preview.loadError {
            errorState(message: error)
        } else if !preview.isReady {
            ProgressView().tint(Theme.Color.accent)
        } else {
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
    }

    private var videoPanel: some View {
        TrimPlayerSurface(player: preview.player)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)
            .overlay(alignment: .bottom) {
                HStack {
                    Button {
                        preview.togglePlayPause()
                    } label: {
                        Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Theme.Color.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(SpeedFormatter.timestamp(preview.currentTime)) / \(SpeedFormatter.timestamp(preview.duration))")
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
                duration: max(preview.duration, 0.001),
                currentTime: preview.currentTime,
                trimStart: $trimStart,
                trimEnd: $trimEnd,
                onSeek: { preview.seek(to: $0) }
            )
            HStack {
                rangeChip(
                    label: "Start",
                    value: trimStart,
                    set: {
                        trimStart = preview.currentTime
                        if trimEnd <= trimStart + 0.05 {
                            trimEnd = min(preview.duration, trimStart + 0.5)
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
                        trimEnd = preview.currentTime
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
            Text("Trimming replaces the clip's source with a new file. Patterns, loops, and beat times are kept and shifted to the new timeline; anything outside the kept window is dropped.")
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

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
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

    // MARK: - Apply

    private var canApply: Bool {
        preview.duration > 0
            && trimEnd - trimStart > 0.05
            && (trimStart > 0.05 || trimEnd < preview.duration - 0.05)
    }

    private func applyTrim() async {
        guard let asset = preview.player.currentItem?.asset else {
            exportError = "Clip isn't ready yet."
            return
        }
        preview.pause()
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
        // Drop the old trimmed file (if this clip was trimmed before) so we
        // don't leak the previous sandbox file when the new one supersedes it.
        if let previous = clip.trimmedFileName {
            TrimStorage.deleteIfExists(name: previous)
        }
        clip.trimmedFileName = fileName
        clip.durationSeconds = newDuration

        // Shift annotations onto the new timeline.
        let start = trimStart
        let end = trimEnd
        clip.firstDownbeatSeconds = clip.firstDownbeatSeconds.flatMap {
            TrimAnnotationShifter.shiftPoint($0, trimStart: start, trimEnd: end)
        }
        clip.setBeatTimes(
            TrimAnnotationShifter.shiftBeatTimes(clip.beatTimes, trimStart: start, trimEnd: end)
        )

        for marker in clip.loopMarkers {
            if let shifted = TrimAnnotationShifter.shiftRange(
                start: marker.startSeconds,
                end: marker.endSeconds,
                trimStart: start,
                trimEnd: end
            ) {
                marker.startSeconds = shifted.start
                marker.endSeconds = shifted.end
            } else {
                modelContext.delete(marker)
            }
        }

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
                // Track.
                Capsule()
                    .fill(Theme.Color.surfaceElevated)
                    .frame(height: 8)

                // Trimmed-out shaded regions.
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: max(0, startX), height: 30)
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: max(0, width - endX), height: 30)
                    .offset(x: endX)

                // Selected window.
                Capsule()
                    .fill(Theme.Color.accentSoft)
                    .frame(width: max(2, endX - startX), height: 12)
                    .offset(x: startX)

                // Playhead.
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: 28)
                    .offset(x: max(0, playX - 1))

                // Start handle.
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

                // End handle.
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
