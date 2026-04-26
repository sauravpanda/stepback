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

    init(clip: DanceClip) {
        self.clip = clip
        _vm = StateObject(
            wrappedValue: PracticePlayerViewModel(
                assetIdentifier: clip.assetIdentifier,
                localFileURL: clip.trimmedFileURL
            )
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Button {
                        editSheetPresented = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    .accessibilityLabel("Edit clip")
                    Button {
                        // Park the parent VM in a neutral state — loop bounds and
                        // segment selection would fight TrimView's own seeking
                        // since they share an AVPlayer.
                        vm.pause()
                        vm.clearLoop()
                        trimSheetPresented = true
                    } label: {
                        Image(systemName: "crop")
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    .accessibilityLabel("Trim clip")
                    Button {
                        comparePickerPresented = true
                    } label: {
                        Image(systemName: "rectangle.2.swap")
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    .accessibilityLabel("Compare with another clip")
                    Button {
                        vm.toggleMirror()
                    } label: {
                        Image(systemName: vm.mirrored
                            ? "rectangle.portrait.on.rectangle.portrait.angled.fill"
                            : "rectangle.portrait.on.rectangle.portrait.angled"
                        )
                        .foregroundStyle(vm.mirrored ? Theme.Color.accent : Theme.Color.textPrimary)
                    }
                    .accessibilityLabel(vm.mirrored ? "Unmirror video" : "Mirror video")
                }
            }
        }
        .task { await vm.load() }
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
            Task { await vm.reloadAsset(localFileURL: clip.trimmedFileURL) }
        }) {
            TrimView(clip: clip, player: vm.player, initialDuration: vm.duration)
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
                PlayerSurface(player: vm.player)
                    .scaleEffect(x: vm.mirrored ? -1 : 1, y: 1)
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
        return VStack(spacing: 14) {
            HStack {
                BPMBadge(
                    bpm: clip.bpm,
                    isAnalyzing: vm.isAnalyzingBeats,
                    measurePosition: measurePosition,
                    beatsPerMeasure: clip.beatsPerMeasure,
                    onDetect: { Task { await detectBeats() } },
                    onRescale: clip.hasBeatAnalysis ? rescaleBeats : nil
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
            loopControls
            HStack(spacing: 32) {
                Spacer()
                FrameStepButton(systemName: "backward.frame.fill") {
                    vm.stepBackward()
                }
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
                FrameStepButton(systemName: "forward.frame.fill") {
                    vm.stepForward()
                }
                Spacer()
            }
            SpeedPills(selected: vm.speed, onSelect: vm.setSpeed(_:))
            SegmentList(
                segments: clip.segments.sorted { ($0.orderIndex, $0.startSeconds) < ($1.orderIndex, $1.startSeconds) },
                activeID: vm.activeSegmentID,
                onPlay: vm.playSegment,
                onEdit: { editingSegment = $0 }
            )
        }
        .padding(16)
    }

    private var loopControls: some View {
        HStack(spacing: 10) {
            LoopButton(
                label: "A",
                filled: vm.loopStart != nil,
                caption: vm.loopStart.map(SpeedFormatter.timestamp)
            ) {
                vm.markLoopStart()
            }
            LoopButton(
                label: "B",
                filled: vm.loopEnd != nil,
                caption: vm.loopEnd.map(SpeedFormatter.timestamp)
            ) {
                vm.markLoopEnd()
            }
            Spacer()
            if vm.hasLoopRegion {
                Button {
                    splitSheetPresented = true
                } label: {
                    Label("Split", systemImage: "scissors")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save A–B as new pattern")
            }
            if vm.loopStart != nil || vm.loopEnd != nil {
                Button {
                    vm.clearLoop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear loop")
            }
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
    }

    fileprivate func deleteSegment(_ segment: ClipSegment) {
        modelContext.delete(segment)
        try? modelContext.save()
    }

    fileprivate func detectBeats() async {
        await vm.detectBeats(for: clip) {
            try? modelContext.save()
        }
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
                Image(systemName: isActive ? "waveform" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isActive ? .black : Theme.Color.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isActive ? Theme.Color.accent : Theme.Color.accentSoft)
                    )
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
