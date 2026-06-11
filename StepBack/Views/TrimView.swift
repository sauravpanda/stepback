import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import UIKit

/// Modal trim editor. Loads the clip's *original* asset (not the parent's
/// trimmed player), so a trim can be widened as well as narrowed and never
/// degrades quality by trimming an already-trimmed file. The parent frees
/// its decoder while this is open so we don't double the in-memory buffers.
///
/// Picks a [start, end] window with two handles, exports that range from the
/// original, and rebases all annotations onto the new timeline. The kept
/// window is recorded in the trim filename so the next edit can re-source
/// from the original.
struct TrimView: View {

    let clip: DanceClip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let photosService: PhotosServicing

    @State private var player = AVPlayer()
    @State private var sourceAsset: AVURLAsset?
    /// Offset (seconds) from the current annotation timeline to the source
    /// asset's timeline. >0 when re-trimming a clip whose existing trim began
    /// `sourceOffset` into the original; 0 for a first trim or the fallback.
    @State private var sourceOffset: Double = 0
    /// True when trimming the full original (handles can widen); false when
    /// we fell back to the already-trimmed file (narrow only).
    @State private var sourceIsOriginal = false

    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var isReady = false
    @State private var loadError: String?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var timeObserver: Any?

    init(clip: DanceClip, photosService: PhotosServicing = PhotosService()) {
        self.clip = clip
        self.photosService = photosService
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
        .task { await loadSource() }
        .onDisappear { detachTimeObserver() }
        .keepScreenAwake()
        .preferredColorScheme(.dark)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Theme.Color.accent)
                Text("Couldn't open this clip to trim")
                    .font(Theme.Font.bodyEmphasized)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(loadError)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        } else if !isReady {
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
        PlayerSurface(player: player)
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
            Text(sourceIsOriginal ? "Re-editable trim" : "Heads up")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
            Text(sourceIsOriginal
                ? "Trim is re-exported from your original video, so you can widen or narrow it later. Patterns and beat times are shifted to the new window; any that fall outside it are dropped."
                : "Trimming replaces the clip's source with a new file. Patterns and beat times are shifted to the new window; anything outside it is dropped.")
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

    // MARK: - Loading the source

    private func loadSource() async {
        do {
            let resolved = try await resolveTrimSource()
            let loaded = (try? await resolved.asset.load(.duration).seconds) ?? 0
            guard loaded.isFinite, loaded > 0 else {
                loadError = "Couldn't read the clip's length."
                return
            }
            sourceAsset = resolved.asset
            sourceOffset = resolved.offset
            sourceIsOriginal = resolved.isOriginal
            duration = loaded

            // Open showing the current trim window when we can map it onto the
            // source (re-editing from the original); otherwise the whole source.
            if resolved.isOriginal,
               let name = clip.trimmedFileName,
               let bounds = TrimStorage.bounds(fromName: name) {
                trimStart = max(0, min(bounds.start, loaded))
                trimEnd = max(trimStart + 0.05, min(bounds.end, loaded))
            } else {
                trimStart = 0
                trimEnd = loaded
            }

            let item = AVPlayerItem(asset: resolved.asset)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            isReady = true
            seek(to: trimStart)
            attachTimeObserver()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Decides what to trim from and how the current annotation timeline maps
    /// onto it. Prefers the full original (so the trim can widen) whenever the
    /// offset is known — i.e. the clip was never trimmed, or its trim filename
    /// records its source range. Falls back to the already-trimmed file
    /// (narrow only) for legacy trims or when the original is gone.
    private func resolveTrimSource() async throws
        -> (asset: AVURLAsset, offset: Double, isOriginal: Bool) {
        let parsedStart = clip.trimmedFileName
            .flatMap { TrimStorage.bounds(fromName: $0)?.start }
        let offsetKnown = clip.trimmedFileName == nil || parsedStart != nil

        if offsetKnown {
            if let url = clip.originalFileURL {
                return (AVURLAsset(url: url), parsedStart ?? 0, true)
            }
            if let urlAsset = try? await photosService.resolveAVAsset(for: clip.assetIdentifier) {
                return (urlAsset, parsedStart ?? 0, true)
            }
        }

        // Fallback: trim the current playable file. Annotations already align
        // with it (offset 0), but we can only narrow.
        if let url = clip.preferredLocalFileURL {
            return (AVURLAsset(url: url), 0, false)
        }
        if let urlAsset = try? await photosService.resolveAVAsset(for: clip.assetIdentifier) {
            return (urlAsset, 0, false)
        }
        throw TrimError.exportFailed("Couldn't load the clip to trim.")
    }

    // MARK: - Apply

    private var canApply: Bool {
        isReady && duration > 0 && trimEnd - trimStart > 0.05
    }

    private func applyTrim() async {
        guard let asset = sourceAsset else {
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
                end: trimEnd,
                recordsOriginalBounds: sourceIsOriginal
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

        // Annotations live in the *current* timeline. Express the new window
        // there too (subtract the source offset) so widening — where
        // newStart < sourceOffset, making rebaseStart negative — shifts them
        // forward correctly instead of dropping them.
        let rebaseStart = trimStart - sourceOffset
        let rebaseEnd = trimEnd - sourceOffset

        clip.firstDownbeatSeconds = clip.firstDownbeatSeconds.flatMap {
            TrimAnnotationShifter.shiftPoint($0, trimStart: rebaseStart, trimEnd: rebaseEnd)
        }
        clip.setBeatTimes(
            TrimAnnotationShifter.shiftBeatTimes(clip.beatTimes, trimStart: rebaseStart, trimEnd: rebaseEnd)
        )

        for segment in clip.segments {
            if let shifted = TrimAnnotationShifter.shiftRange(
                start: segment.startSeconds,
                end: segment.endSeconds,
                trimStart: rebaseStart,
                trimEnd: rebaseEnd
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
