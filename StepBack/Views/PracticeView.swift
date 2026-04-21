import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import UIKit

struct PracticeView: View {

    let clip: DanceClip

    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: PracticePlayerViewModel
    @State private var markerSheetPresented = false
    @State private var comparePickerPresented = false
    @State private var compareSecondary: DanceClip?

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
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
        .sheet(isPresented: $markerSheetPresented) {
            SaveMarkerSheet(
                defaultSpeed: vm.speed,
                defaultRegion: (vm.loopStart ?? 0, vm.loopEnd ?? 0)
            ) { label, speed in
                saveMarker(label: label, speed: speed)
            }
            .presentationDetents([.medium])
        }
    }

    private func saveMarker(label: String, speed: Double) {
        guard let start = vm.loopStart, let end = vm.loopEnd, end > start else { return }
        let marker = LoopMarker(
            label: label,
            startSeconds: start,
            endSeconds: end,
            preferredSpeed: speed,
            clip: clip
        )
        modelContext.insert(marker)
        try? modelContext.save()
    }

    private func deleteMarker(_ marker: LoopMarker) {
        modelContext.delete(marker)
        try? modelContext.save()
    }

    private func detectBeats() async {
        await vm.detectBeats(for: clip) {
            try? modelContext.save()
        }
    }

    private func tapOnBeatOne() {
        vm.tapOnBeatOne(for: clip) {
            try? modelContext.save()
        }
    }

    private func clearDownbeat() {
        vm.clearDownbeatAnchor(for: clip) {
            try? modelContext.save()
        }
    }

    private func rescaleBeats(by factor: Double) {
        vm.rescaleBeats(for: clip, factor: factor) {
            try? modelContext.save()
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
            MarkerList(
                markers: clip.loopMarkers.sorted { $0.startSeconds < $1.startSeconds },
                onApply: vm.applyMarker,
                onDelete: deleteMarker
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
                    markerSheetPresented = true
                } label: {
                    Label("Save", systemImage: "bookmark.fill")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Color.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
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

// MARK: - Markers

private struct MarkerList: View {
    let markers: [LoopMarker]
    let onApply: (LoopMarker) -> Void
    let onDelete: (LoopMarker) -> Void

    var body: some View {
        if markers.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(markers) { marker in
                        MarkerChip(marker: marker, onApply: onApply, onDelete: onDelete)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct MarkerChip: View {
    let marker: LoopMarker
    let onApply: (LoopMarker) -> Void
    let onDelete: (LoopMarker) -> Void

    var body: some View {
        Button {
            onApply(marker)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.label)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(SpeedFormatter.timestamp(marker.startSeconds))
                    Text("–")
                    Text(SpeedFormatter.timestamp(marker.endSeconds))
                    Text("·")
                    Text(SpeedFormatter.pill(marker.preferredSpeed))
                }
                .font(Theme.Font.timestamp)
                .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(marker)
            } label: {
                Label("Delete marker", systemImage: "trash")
            }
        }
    }
}

// MARK: - Save marker sheet

private struct SaveMarkerSheet: View {
    let defaultSpeed: Double
    let defaultRegion: (start: Double, end: Double)
    let onSave: (String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
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
                Section("Name") {
                    TextField("Hard 8-count", text: $label)
                }
                Section("Region") {
                    LabeledContent("Start", value: SpeedFormatter.timestamp(defaultRegion.start))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("End", value: SpeedFormatter.timestamp(defaultRegion.end))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Section("Preferred speed") {
                    SpeedPills(selected: speed, onSelect: { speed = $0 })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Save loop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? "Marker" : trimmed, speed)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
