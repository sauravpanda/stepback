import SwiftData
import SwiftUI
import UIKit

// MARK: - Persistence + command helpers

extension PracticeView {
    func saveSegment(title: String, preferredSpeed: Double) {
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

    func deleteSegment(_ segment: ClipSegment) {
        modelContext.delete(segment)
        try? modelContext.save()
    }

    /// A swipe on the video: move to the neighbour in that direction, if
    /// there is one. At either end of the list the swipe does nothing, and
    /// the absence of the usual tick says why.
    func openNeighbor(_ direction: PlayerSwipe.Direction) {
        let target = direction == .toNext ? neighbors.next : neighbors.previous
        guard let target, let onOpenNeighbor else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onOpenNeighbor(target, direction)
    }

    func detectBeats() async {
        await vm.detectBeats(for: clip) {
            try? modelContext.save()
        }
        configureBeatPulse()
    }

    func configureBeatPulse() {
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

    func tapOnBeatOne() {
        vm.tapOnBeatOne(for: clip) {
            try? modelContext.save()
        }
    }

    func clearDownbeat() {
        vm.clearDownbeatAnchor(for: clip) {
            try? modelContext.save()
        }
    }

    func rescaleBeats(by factor: Double) {
        vm.rescaleBeats(for: clip, factor: factor) {
            try? modelContext.save()
        }
    }
}
