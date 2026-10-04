import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import UIKit

struct PracticeView: View {

    let clip: DanceClip
    /// The clips either side of this one in the list it was opened from,
    /// so a swipe on the video moves on without a trip back to the Library.
    let neighbors: ClipNeighbors
    /// Asked to show a neighbour after a swipe; the caller owns navigation.
    let onOpenNeighbor: ((DanceClip, PlayerSwipe.Direction) -> Void)?
    /// Start playing as soon as the clip has loaded. Set when the clip was
    /// swiped to: moving on shouldn't also mean pressing play again.
    let autoplay: Bool

    // Internal rather than private: the PracticeView+*.swift extensions
    // read the model context and the player view model too.
    @Environment(\.modelContext) var modelContext
    @StateObject var vm: PracticePlayerViewModel
    @State private var splitSheetPresented = false
    @State private var editingSegment: ClipSegment?
    @State private var trimSheetPresented = false
    @State private var editSheetPresented = false
    /// Hides the entire control stack so the video can claim the screen.
    /// Single-tap on the video remains wired to play/pause so pausing
    /// doesn't require bringing controls back first.
    @State private var controlsHidden: Bool = false
    /// Debug: ring every detected person so hops are diagnosable from a
    /// screen recording.
    @State private var poseDebug: Bool = false
    /// Beats and phrase changes drawn over the video. A habit rather than a
    /// per-clip fact, so it's remembered across clips.
    @AppStorage(SettingsKeys.beatOverlay) private var beatOverlayOn = false
    /// The Trim / Save-pattern row. Off by default: it cost a row of the
    /// video's height on every clip for two actions most sessions never use.
    @AppStorage(SettingsKeys.showTrimTools) private var showTrimTools = false
    @StateObject private var poseCoordinator: PoseStreamCoordinator

    init(
        clip: DanceClip,
        neighbors: ClipNeighbors = .none,
        onOpenNeighbor: ((DanceClip, PlayerSwipe.Direction) -> Void)? = nil,
        autoplay: Bool = false
    ) {
        self.clip = clip
        self.neighbors = neighbors
        self.onOpenNeighbor = onOpenNeighbor
        self.autoplay = autoplay
        // Share a single AVPlayer between the view model and the pose
        // coordinator so the coordinator's video output reads frames from
        // the *same* item the user is watching.
        let sharedPlayer = AVPlayer()
        _vm = StateObject(
            wrappedValue: PracticePlayerViewModel(
                assetIdentifier: clip.assetIdentifier,
                cloudIdentifier: clip.cloudAssetIdentifier,
                localFileURL: clip.preferredLocalFileURL,
                player: sharedPlayer,
                onLocalIdentifierRemapped: { healed in
                    clip.assetIdentifier = healed
                    try? clip.modelContext?.save()
                }
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
            // "trim clip" at a glance. Rotate stays here because it's rarer
            // and ergonomic next to the title.
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Favourite lives here as well as in the Library: the
                    // moment you know a clip is worth coming back to is
                    // while you're practising it.
                    Button {
                        clip.isFavorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: clip.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(clip.isFavorite ? Theme.Color.accent : Theme.Color.textPrimary)
                    }
                    .accessibilityLabel(clip.isFavorite ? "Remove from Favorites" : "Favorite")
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            vm.rotate()
                        }
                    } label: {
                        Label("Rotate", systemImage: "rotate.right")
                            .labelStyle(.titleAndIcon)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(vm.rotationQuarterTurns != 0
                                ? Theme.Color.accent
                                : Theme.Color.textPrimary
                            )
                    }
                    .accessibilityLabel(vm.rotationQuarterTurns == 0
                        ? "Rotate video"
                        : "Rotate video, currently \(vm.rotationQuarterTurns * 90) degrees"
                    )
                }
            }
        }
        .task {
            await vm.load()
            configureBeatPulse()
            if autoplay, vm.isReady {
                vm.play()
            }
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
        .fullScreenCover(
            isPresented: $trimSheetPresented,
            onDismiss: {
                // After a trim the underlying file has changed; rebind the player.
                // Fall through to the sandboxed original if the user backed out
                // of the trim sheet without exporting.
                Task { await vm.reloadAsset(localFileURL: clip.preferredLocalFileURL) }
            },
            content: {
                // TrimView loads the original in its own player, so it no longer
                // shares ours.
                TrimView(clip: clip)
            }
        )
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
}

extension PracticeView {
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
                    onLongPressLocated: { fraction in pinDancer(atContainerFraction: fraction) },
                    onSwipe: openNeighbor,
                    content: {
                        // Rotation: size the surface to axis-swapped bounds for
                        // 90°/270° so the rotated result aspect-fits the
                        // container, then spin it into place. The pose overlay
                        // sits inside the same frame, so the skeleton rotates in
                        // lockstep with the pixels it annotates.
                        GeometryReader { geo in
                            let quarterTurns = vm.rotationQuarterTurns
                            let swapAxes = quarterTurns % 2 == 1
                            ZStack {
                                PlayerSurface(player: vm.player)
                                if poseCoordinator.isActive {
                                    PoseOverlay(
                                        pose: poseCoordinator.pose,
                                        imageSize: poseCoordinator.imageSize,
                                        poseAge: poseCoordinator.poseAge,
                                        debugCandidates: poseDebug ? poseCoordinator.candidates : []
                                    )
                                }
                            }
                            .frame(
                                width: swapAxes ? geo.size.height : geo.size.width,
                                height: swapAxes ? geo.size.width : geo.size.height
                            )
                            .rotationEffect(.degrees(Double(quarterTurns) * 90))
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    }
                )
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
                .overlay {
                    // Pinned to the bottom of the *picture*, not the player
                    // area: a landscape clip on a portrait phone is a band
                    // across the middle, and an overlay at the area's edge
                    // would sit in the black beneath it.
                    if beatOverlayOn, clip.hasBeatAnalysis {
                        GeometryReader { geo in
                            let frame = VideoFrame.aspectFitRect(
                                videoSize: vm.videoSize,
                                in: geo.size,
                                quarterTurns: vm.rotationQuarterTurns
                            )
                            PracticeBeatOverlay(vm: vm, clip: clip)
                                .frame(width: frame.width, height: frame.height, alignment: .bottom)
                                .position(x: frame.midX, y: frame.midY)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // On the video rather than in the control stack: it
                    // stays reachable with the controls hidden, and the BPM
                    // row has no room for another chip.
                    if clip.hasBeatAnalysis {
                        Button {
                            beatOverlayOn.toggle()
                        } label: {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(beatOverlayOn ? .black : Theme.Color.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(
                                    beatOverlayOn ? Theme.Color.accent : Color.black.opacity(0.55),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(beatOverlayOn ? "Hide beats on video" : "Show beats on video")
                        .padding(10)
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
        // The press arrives in rotated-display space; undo the rotation
        // first so it lines up with the unrotated video frame.
        let unrotated = PoseCoordinateTransform.unrotatedFraction(
            fraction,
            quarterTurns: vm.rotationQuarterTurns
        )
        let unitRect = PoseCoordinateTransform.displayRect(
            imageSize: imageSize,
            in: CGSize(width: 1, height: 1)
        )
        guard let imagePoint = PoseCoordinateTransform.normalizedImagePoint(
            containerFraction: unrotated,
            unitDisplayRect: unitRect
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
            PlayerScrubber(
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

    /// Discoverable, always-visible row for trim + pattern. The Split button
    /// used to live inside `loopControls` and only appeared when both A and
    /// B were set — fine for users who already knew the workflow, invisible
    /// for everyone else. The trim icon was buried in the top toolbar with
    /// no label. Promoting both to labeled pills here makes the two main
    /// "edit this clip" actions obvious from the practice surface.
    @ViewBuilder
    private var actionRow: some View {
        if showTrimTools {
            actionRowContent
        }
    }

    private var actionRowContent: some View {
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
