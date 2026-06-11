import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import UIKit

struct PracticeView: View {

    let clip: DanceClip

    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: PracticePlayerViewModel
    @State private var splitSheetPresented = false
    @State private var editingSegment: ClipSegment?
    @State private var trimSheetPresented = false
    @State private var comparePickerPresented = false
    @State private var compareSecondary: DanceClip?
    @State private var editSheetPresented = false
    /// Hides the entire control stack so the video can claim the screen.
    /// Single-tap on the video remains wired to play/pause so pausing
    /// doesn't require bringing controls back first.
    @State private var controlsHidden: Bool = false
    /// Debug: ring every detected person so hops are diagnosable from a
    /// screen recording.
    @State private var poseDebug: Bool = false
    @StateObject private var poseCoordinator: PoseStreamCoordinator

    init(clip: DanceClip) {
        self.clip = clip
        // Share a single AVPlayer between the view model and the pose
        // coordinator so the coordinator's video output reads frames from
        // the *same* item the user is watching.
        let sharedPlayer = AVPlayer()
        _vm = StateObject(
            wrappedValue: PracticePlayerViewModel(
                assetIdentifier: clip.assetIdentifier,
                localFileURL: clip.preferredLocalFileURL,
                player: sharedPlayer
            )
        )
        _poseCoordinator = StateObject(
            wrappedValue: PoseStreamCoordinator(player: sharedPlayer)
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
        .toolbar {
            // Trim moved into the inline action row below the scrubber for
            // discoverability — the chrome icon was hard to associate with
            // "trim clip" at a glance. Compare and Mirror stay here because
            // they're rarer and ergonomic next to the title.
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            controlsHidden.toggle()
                        }
                    } label: {
                        Image(systemName: controlsHidden ? "chevron.up" : "chevron.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(controlsHidden ? Theme.Color.accent : Theme.Color.textPrimary)
                    }
                    .accessibilityLabel(controlsHidden ? "Show controls" : "Hide controls")
                    Button {
                        editSheetPresented = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    .accessibilityLabel("Edit clip")
                    Button {
                        if poseCoordinator.isActive {
                            poseCoordinator.stop()
                        } else {
                            poseCoordinator.start()
                        }
                    } label: {
                        Image(systemName: poseCoordinator.isActive
                            ? "figure.walk.motion"
                            : "figure.walk"
                        )
                        .foregroundStyle(poseCoordinator.isActive
                            ? Theme.Color.accent
                            : Theme.Color.textPrimary
                        )
                    }
                    .accessibilityLabel(poseCoordinator.isActive
                        ? "Disable pose detection"
                        : "Enable pose detection"
                    )
                    Button {
                        comparePickerPresented = true
                    } label: {
                        Label("Compare", systemImage: "rectangle.2.swap")
                            .labelStyle(.titleAndIcon)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    .accessibilityLabel("Compare with another clip")
                    Button {
                        vm.toggleMirror()
                    } label: {
                        Label("Mirror", systemImage: vm.mirrored
                            ? "rectangle.portrait.on.rectangle.portrait.angled.fill"
                            : "rectangle.portrait.on.rectangle.portrait.angled"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(vm.mirrored ? Theme.Color.accent : Theme.Color.textPrimary)
                    }
                    .accessibilityLabel(vm.mirrored ? "Unmirror video" : "Mirror video")
                }
            }
        }
        .task {
            await vm.load()
            configureBeatPulse()
        }
        .onChange(of: clip.beatTimesData) { _, _ in
            // Re-arm the boundary observer when beats are (re-)detected so
            // the pulse comes online without requiring a view re-entry.
            configureBeatPulse()
        }
        .onChange(of: clip.firstDownbeatSeconds) { _, _ in
            // Anchor changes don't change *which* times pulse, but they do
            // change which are downbeats — re-arm so the bigger-on-1 logic
            // tracks the new measure boundaries.
            configureBeatPulse()
        }
        .onAppear { vm.enableNowPlaying(for: clip) }
        .onDisappear {
            // Stop playback when leaving the screen. Without this the player
            // keeps going after you navigate back (audio session is .playback
            // + Background Audio), and opening another clip stacks a second
            // player over the first → overlapping audio. onDisappear fires on
            // *navigation*, not on app-backgrounding, so locking the phone
            // still keeps audio playing as intended.
            vm.pause()
            vm.disableNowPlaying()
            poseCoordinator.stop()
        }
        .keepScreenAwake()
        .sheet(isPresented: $comparePickerPresented) {
            CompareClipPicker(excludedID: clip.id) { picked in
                compareSecondary = picked
            }
        }
        .navigationDestination(item: $compareSecondary) { secondary in
            CompareView(primary: clip, secondary: secondary)
        }
        .sheet(isPresented: $editSheetPresented) {
            ClipEditView(clip: clip)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $splitSheetPresented) {
            SegmentSaveSheet(
                defaultSpeed: vm.speed,
                defaultRegion: (vm.loopStart ?? 0, vm.loopEnd ?? 0)
            ) { title, speed in
                saveSegment(title: title, preferredSpeed: speed)
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $trimSheetPresented, onDismiss: {
            // After a trim the underlying file has changed; rebind the player.
            // Fall through to the sandboxed original if the user backed out
            // of the trim sheet without exporting.
            Task { await vm.reloadAsset(localFileURL: clip.preferredLocalFileURL) }
        }) {
            // TrimView loads the original in its own player, so it no longer
            // shares ours.
            TrimView(clip: clip)
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditSheet(
                segment: segment,
                onDelete: {
                    if vm.activeSegmentID == segment.id {
                        vm.clearActiveSegment()
                    }
                    deleteSegment(segment)
                }
            )
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
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
                // Don't constrain to 16:9 here — AVPlayerLayer's .resizeAspect
                // already letterboxes the actual video. A rigid ratio on this
                // container double-letterboxes (big black bands top/bottom on
                // tall phone screens for any non-16:9 source). Let the video
                // claim leftover vertical space; controls keep their intrinsic
                // height and float beneath.
                ZoomablePlayerContainer(
                    onSingleTap: { vm.togglePlayPause() },
                    onLongPressLocated: { fraction in pinDancer(atContainerFraction: fraction) }
                ) {
                    ZStack {
                        PlayerSurface(player: vm.player)
                            .scaleEffect(x: vm.mirrored ? -1 : 1, y: 1)
                        if poseCoordinator.isActive {
                            // Mirror the overlay alongside the video so the
                            // skeleton tracks the actual displayed body, not
                            // the original frame's body.
                            PoseOverlay(
                                pose: poseCoordinator.pose,
                                imageSize: poseCoordinator.imageSize,
                                poseAge: poseCoordinator.poseAge,
                                debugCandidates: poseDebug ? poseCoordinator.candidates : []
                            )
                            .scaleEffect(x: vm.mirrored ? -1 : 1, y: 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .layoutPriority(1)
                .overlay(alignment: .topLeading) {
                    if poseCoordinator.isActive {
                        VStack(alignment: .leading, spacing: 6) {
                            PoseStatusChip(status: poseCoordinator.status)
                            poseTrackingControl
                            poseDebugToggle
                        }
                        .padding(.leading, 10)
                        .padding(.top, 10)
                    }
                }

                if !controlsHidden {
                    controls
                        // Slide down + fade so the controls feel anchored to
                        // the bottom edge; an opacity-only swap pops, and a
                        // height collapse without a translation reads as a
                        // glitch.
                        .transition(
                            .move(edge: .bottom)
                            .combined(with: .opacity)
                        )
                }
            }
            // Without an explicit fill, the parent ZStack's default centering
            // can leave dead space at the bottom even when children are
            // flexible — `layoutPriority` only redistributes within the size
            // proposed to the VStack. Pin to the full ZStack so the player
            // stretches to the top of the controls.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Lock badge / release button (when pinned) or a hold-to-lock hint
    /// (when tracking automatically). Sits under the pose status chip.
    @ViewBuilder
    private var poseTrackingControl: some View {
        if poseCoordinator.isPinned {
            Button {
                poseCoordinator.unpin()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Locked · Release")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Hold a dancer to lock")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
        }
    }

    /// Small debug toggle: rings every detected person so a screen recording
    /// shows which body the tracker locked onto and which it skipped.
    private var poseDebugToggle: some View {
        Button {
            poseDebug.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: poseDebug ? "ladybug.fill" : "ladybug")
                    .font(.system(size: 10, weight: .semibold))
                Text(poseDebug ? "Debug on" : "Debug")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(poseDebug ? .cyan : Theme.Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Maps a long-press location (as a fraction of the un-zoomed player
    /// container) back to a normalized Vision image point and pins the
    /// dancer nearest it. No-op when pose detection is off or the frame
    /// size isn't known yet.
    private func pinDancer(atContainerFraction fraction: CGPoint) {
        guard poseCoordinator.isActive, let imageSize = poseCoordinator.imageSize else { return }
        let unitRect = PoseCoordinateTransform.displayRect(
            imageSize: imageSize,
            in: CGSize(width: 1, height: 1)
        )
        guard let imagePoint = PoseCoordinateTransform.normalizedImagePoint(
            containerFraction: fraction,
            unitDisplayRect: unitRect,
            mirrored: vm.mirrored
        ) else { return }
        poseCoordinator.pin(at: imagePoint)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        let downbeats = BeatGrid.downbeatIndices(
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            beatsPerMeasure: clip.beatsPerMeasure
        )
        let measurePosition = BeatGrid.currentMeasurePosition(
            currentTime: vm.currentTime,
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            beatsPerMeasure: clip.beatsPerMeasure
        )
        return VStack(spacing: 10) {
            HStack {
                BPMBadge(
                    bpm: clip.bpm,
                    isAnalyzing: vm.isAnalyzingBeats,
                    measurePosition: measurePosition,
                    beatsPerMeasure: clip.beatsPerMeasure,
                    onDetect: { Task { await detectBeats() } },
                    onRescale: clip.hasBeatAnalysis ? rescaleBeats : nil,
                    beatPulseID: vm.beatPulseID,
                    lastBeatWasDownbeat: vm.lastBeatWasDownbeat
                )
                Spacer()
            }
            if clip.hasBeatAnalysis {
                DownbeatAnchorBar(
                    hasAnchor: clip.firstDownbeatSeconds != nil,
                    onTap: tapOnBeatOne,
                    onClear: clearDownbeat
                )
                StepTimingPanel(
                    taps: vm.stepTaps,
                    isActive: vm.stepTimingActive,
                    onToggle: vm.toggleStepTiming,
                    onTap: { vm.recordStepTap(against: clip.beatTimes) },
                    onReset: vm.clearStepTaps
                )
            }
            Scrubber(
                currentTime: vm.currentTime,
                duration: vm.duration,
                loopStart: vm.loopStart,
                loopEnd: vm.loopEnd,
                beatTimes: clip.beatTimes,
                downbeatIndices: downbeats,
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
            actionRow
            transportRow
            SegmentList(
                segments: clip.segments.sorted { ($0.orderIndex, $0.startSeconds) < ($1.orderIndex, $1.startSeconds) },
                activeID: vm.activeSegmentID,
                onPlay: vm.playSegment,
                onEdit: { editingSegment = $0 }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Single-row transport: A/B markers on the left, frame-step + play in
    /// the middle, speed selector on the right. Replaces the previous
    /// three rows (loop controls / play / speed pills) — which together
    /// cost ~150pt of vertical chrome on every clip. The compact A/B
    /// timestamps drop from the buttons here; the loop region is already
    /// rendered on the scrubber, and the Trim/Save Pattern action row above
    /// confirms the action visually when the user does something with A/B.
    private var transportRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                LoopButton(
                    label: "A",
                    filled: vm.loopStart != nil,
                    caption: nil
                ) {
                    vm.markLoopStart()
                }
                LoopButton(
                    label: "B",
                    filled: vm.loopEnd != nil,
                    caption: nil
                ) {
                    vm.markLoopEnd()
                }
                if vm.loopStart != nil || vm.loopEnd != nil {
                    Button {
                        vm.clearLoop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear loop")
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 18) {
                FrameStepButton(systemName: "backward.frame.fill") {
                    vm.stepBackward()
                }
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Theme.Color.accent, in: Circle())
                }
                .buttonStyle(.plain)
                FrameStepButton(systemName: "forward.frame.fill") {
                    vm.stepForward()
                }
            }
            Spacer(minLength: 8)
            SpeedMenuButton(selected: vm.speed, onSelect: vm.setSpeed(_:))
        }
    }

    /// Discoverable, always-visible row for trim + pattern. The Split button
    /// used to live inside `loopControls` and only appeared when both A and
    /// B were set — fine for users who already knew the workflow, invisible
    /// for everyone else. The trim icon was buried in the top toolbar with
    /// no label. Promoting both to labeled pills here makes the two main
    /// "edit this clip" actions obvious from the practice surface.
    private var actionRow: some View {
        HStack(spacing: 8) {
            ActionPill(
                title: "Trim",
                systemImage: "crop",
                tint: .surface
            ) {
                // Free our decoder while TrimView is open — it loads the
                // original in its own player, and two decoders of a long clip
                // can blow the per-process memory budget. Also stop pose so it
                // isn't polling a player whose item we just removed. The
                // onDismiss reload restores playback.
                vm.pause()
                vm.clearLoop()
                poseCoordinator.stop()
                vm.player.replaceCurrentItem(with: nil)
                trimSheetPresented = true
            }
            ActionPill(
                title: vm.hasLoopRegion ? "Save pattern" : "Set A & B to save",
                systemImage: "scissors",
                tint: vm.hasLoopRegion ? .accent : .surfaceMuted
            ) {
                splitSheetPresented = true
            }
            .disabled(!vm.hasLoopRegion)
            Spacer()
        }
    }
}

/// Labeled pill button for the practice action row. Two visual variants:
/// `.accent` (filled accent) for the primary action when ready, `.surface`
/// for a neutral secondary action, `.surfaceMuted` for a disabled state.
private struct ActionPill: View {
    enum Tint { case accent, surface, surfaceMuted }

    let title: String
    let systemImage: String
    let tint: Tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tint {
        case .accent: .black
        case .surface: Theme.Color.textPrimary
        case .surfaceMuted: Theme.Color.textTertiary
        }
    }

    private var background: Color {
        switch tint {
        case .accent: Theme.Color.accent
        case .surface: Theme.Color.surfaceElevated
        case .surfaceMuted: Theme.Color.surface
        }
    }
}

// MARK: - Persistence + command helpers

extension PracticeView {
    fileprivate func saveSegment(title: String, preferredSpeed: Double) {
        guard let start = vm.loopStart, let end = vm.loopEnd, end > start else { return }
        let nextIndex = (clip.segments.map(\.orderIndex).max() ?? -1) + 1
        let segment = ClipSegment(
            title: title,
            startSeconds: start,
            endSeconds: end,
            preferredSpeed: preferredSpeed,
            orderIndex: nextIndex,
            clip: clip
        )
        modelContext.insert(segment)
        try? modelContext.save()

        // Render the thumbnail off-actor; persist back when ready.
        if let asset = vm.player.currentItem?.asset {
            let segmentID = segment.id
            let startSeconds = start
            Task {
                let data = await SegmentThumbnailGenerator.generate(
                    from: asset,
                    atSeconds: startSeconds
                )
                await MainActor.run {
                    if let stored = clip.segments.first(where: { $0.id == segmentID }) {
                        stored.thumbnailData = data
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    fileprivate func deleteSegment(_ segment: ClipSegment) {
        modelContext.delete(segment)
        try? modelContext.save()
    }

    fileprivate func detectBeats() async {
        await vm.detectBeats(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
    }

    fileprivate func configureBeatPulse() {
        let downbeats = BeatGrid.downbeatIndices(
            beatTimes: clip.beatTimes,
            anchor: clip.firstDownbeatSeconds,
            beatsPerMeasure: clip.beatsPerMeasure
        )
        vm.configureBeatPulse(
            beatTimes: clip.beatTimes,
            downbeatIndices: downbeats
        )
    }

    fileprivate func tapOnBeatOne() {
        vm.tapOnBeatOne(for: clip) {
            try? modelContext.save()
        }
    }

    fileprivate func clearDownbeat() {
        vm.clearDownbeatAnchor(for: clip) {
            try? modelContext.save()
        }
    }

    fileprivate func rescaleBeats(by factor: Double) {
        vm.rescaleBeats(for: clip, factor: factor) {
            try? modelContext.save()
        }
    }
}

// MARK: - Scrubber

private struct Scrubber: View {
    let currentTime: Double
    let duration: Double
    let loopStart: Double?
    let loopEnd: Double?
    let beatTimes: [Double]
    let downbeatIndices: Set<Int>
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
                beatTicksOverlay(width: width)
                loopRegionOverlay(width: width)
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

    @ViewBuilder
    private func beatTicksOverlay(width: CGFloat) -> some View {
        if duration > 0, !beatTimes.isEmpty {
            ZStack(alignment: .leading) {
                ForEach(Array(beatTimes.enumerated()), id: \.offset) { index, time in
                    let isDownbeat = downbeatIndices.contains(index)
                    Rectangle()
                        .fill(isDownbeat ? Theme.Color.accent : Theme.Color.textTertiary.opacity(0.6))
                        .frame(
                            width: isDownbeat ? 2 : 1,
                            height: isDownbeat ? 14 : 8
                        )
                        .offset(x: width * (time / duration))
                }
            }
        }
    }

    @ViewBuilder
    private func loopRegionOverlay(width: CGFloat) -> some View {
        if duration > 0, let start = loopStart, let end = loopEnd, end > start {
            let startX = width * min(1, max(0, start / duration))
            let endX = width * min(1, max(0, end / duration))
            Capsule()
                .fill(Theme.Color.accentSoft)
                .frame(width: max(2, endX - startX), height: 10)
                .offset(x: startX)
            ForEach([startX, endX], id: \.self) { edge in
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(width: 2, height: 14)
                    .offset(x: max(0, edge - 1))
            }
        }
    }
}

// MARK: - Frame step

private struct FrameStepButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loop controls

private struct LoopButton: View {
    let label: String
    let filled: Bool
    let caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(filled ? .black : Theme.Color.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(filled ? Theme.Color.accent : Theme.Color.surfaceElevated)
                    )
                if let caption {
                    Text(caption)
                        .font(Theme.Font.timestamp)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segments

private struct SegmentList: View {
    let segments: [ClipSegment]
    let activeID: UUID?
    let onPlay: (ClipSegment) -> Void
    let onEdit: (ClipSegment) -> Void

    var body: some View {
        if segments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Patterns")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(segments) { segment in
                            SegmentCard(
                                segment: segment,
                                isActive: segment.id == activeID,
                                onPlay: { onPlay(segment) },
                                onEdit: { onEdit(segment) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct SegmentCard: View {
    let segment: ClipSegment
    let isActive: Bool
    let onPlay: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                segmentGlyph
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.title)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(SpeedFormatter.timestamp(segment.startSeconds))
                        Text("–")
                        Text(SpeedFormatter.timestamp(segment.endSeconds))
                        if segment.preferredSpeed != 1.0 {
                            Text("·")
                            Text(SpeedFormatter.pill(segment.preferredSpeed))
                        }
                    }
                    .font(Theme.Font.timestamp)
                    .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.Color.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isActive ? Theme.Color.accent : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
    }

    @ViewBuilder
    private var segmentGlyph: some View {
        if let data = segment.thumbnailData, let uiImage = UIImage(data: data) {
            ZStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.Color.accent.opacity(0.4))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Theme.Color.accent : Color.clear, lineWidth: 1.5)
            )
        } else {
            Image(systemName: isActive ? "waveform" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? .black : Theme.Color.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Theme.Color.accent : Theme.Color.accentSoft)
                )
        }
    }
}

private struct SegmentSaveSheet: View {
    let defaultSpeed: Double
    let defaultRegion: (start: Double, end: Double)
    let onSave: (String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var speed: Double

    init(
        defaultSpeed: Double,
        defaultRegion: (start: Double, end: Double),
        onSave: @escaping (String, Double) -> Void
    ) {
        self.defaultSpeed = defaultSpeed
        self.defaultRegion = defaultRegion
        self.onSave = onSave
        _speed = State(initialValue: defaultSpeed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pattern name") {
                    TextField("Basic step", text: $title)
                }
                Section("Range") {
                    LabeledContent("Start", value: SpeedFormatter.timestamp(defaultRegion.start))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("End", value: SpeedFormatter.timestamp(defaultRegion.end))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("Length", value: SpeedFormatter.timestamp(max(0, defaultRegion.end - defaultRegion.start)))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Section("Practice speed") {
                    SpeedPills(selected: speed, onSelect: { speed = $0 })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("New pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? "Pattern" : trimmed, speed)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SegmentEditSheet: View {
    @Bindable var segment: ClipSegment
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Pattern name", text: $segment.title)
                }
                Section("Range") {
                    LabeledContent("Start", value: SpeedFormatter.timestamp(segment.startSeconds))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("End", value: SpeedFormatter.timestamp(segment.endSeconds))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("Length", value: SpeedFormatter.timestamp(segment.durationSeconds))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Section("Practice speed") {
                    SpeedPills(selected: segment.preferredSpeed, onSelect: { segment.preferredSpeed = $0 })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
                Section("Notes") {
                    TextField("Notes", text: $segment.notes, axis: .vertical)
                        .lineLimit(3...)
                }
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete pattern", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Edit pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
