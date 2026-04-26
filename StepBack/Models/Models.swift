import Foundation
import SwiftData

@Model
final class DanceClip: Equatable, Hashable {
    var id: UUID
    var title: String
    var assetIdentifier: String
    var dateAdded: Date
    var eventName: String?
    var notes: String
    var thumbnailData: Data?
    var durationSeconds: Double

    // Beat analysis, populated once by BeatDetector and cached in the store.
    var bpm: Double?
    var beatTimesData: Data?
    var firstDownbeatSeconds: Double?
    var beatsPerMeasure: Int = 4

    /// Filename (in `TrimStorage.directory`) for a sandboxed trimmed copy of
    /// the original asset. When non-nil, playback resolves to this file
    /// instead of the PHAsset, so trims survive the user deleting the
    /// original from Photos.
    var trimmedFileName: String?

    @Relationship(deleteRule: .cascade, inverse: \LoopMarker.clip)
    var loopMarkers: [LoopMarker] = []

    @Relationship(deleteRule: .cascade, inverse: \ClipSegment.clip)
    var segments: [ClipSegment] = []

    var tags: [Tag] = []

    init(
        id: UUID = UUID(),
        title: String,
        assetIdentifier: String,
        dateAdded: Date = Date(),
        eventName: String? = nil,
        notes: String = "",
        thumbnailData: Data? = nil,
        durationSeconds: Double = 0
    ) {
        self.id = id
        self.title = title
        self.assetIdentifier = assetIdentifier
        self.dateAdded = dateAdded
        self.eventName = eventName
        self.notes = notes
        self.thumbnailData = thumbnailData
        self.durationSeconds = durationSeconds
    }

    static func == (lhs: DanceClip, rhs: DanceClip) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Beat helpers

    /// Decoded beat times (seconds, monotonic). Empty when no analysis exists.
    var beatTimes: [Double] {
        guard let data = beatTimesData else { return [] }
        return (try? JSONDecoder().decode([Double].self, from: data)) ?? []
    }

    /// Writes beat times back through `beatTimesData`. Empty clears the cache.
    func setBeatTimes(_ times: [Double]) {
        if times.isEmpty {
            beatTimesData = nil
            return
        }
        beatTimesData = try? JSONEncoder().encode(times)
    }

    var hasBeatAnalysis: Bool {
        bpm != nil && beatTimesData != nil
    }

    /// Resolved sandbox URL for a trimmed copy, when one exists.
    var trimmedFileURL: URL? {
        guard let trimmedFileName else { return nil }
        return TrimStorage.fileURL(name: trimmedFileName)
    }
}

@Model
final class Tag {
    var id: UUID
    var name: String
    var colorHex: String

    @Relationship(inverse: \DanceClip.tags)
    var clips: [DanceClip] = []

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

@Model
final class LoopMarker {
    var id: UUID
    var label: String
    var startSeconds: Double
    var endSeconds: Double
    var preferredSpeed: Double
    var clip: DanceClip?

    init(
        id: UUID = UUID(),
        label: String,
        startSeconds: Double,
        endSeconds: Double,
        preferredSpeed: Double = 1.0,
        clip: DanceClip? = nil
    ) {
        self.id = id
        self.label = label
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.preferredSpeed = preferredSpeed
        self.clip = clip
    }

    var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }
}

@Model
final class ClipSegment: Equatable, Hashable {
    var id: UUID
    var title: String
    var startSeconds: Double
    var endSeconds: Double
    var preferredSpeed: Double
    var notes: String
    var dateAdded: Date
    var orderIndex: Int
    var clip: DanceClip?

    init(
        id: UUID = UUID(),
        title: String,
        startSeconds: Double,
        endSeconds: Double,
        preferredSpeed: Double = 1.0,
        notes: String = "",
        dateAdded: Date = Date(),
        orderIndex: Int = 0,
        clip: DanceClip? = nil
    ) {
        self.id = id
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.preferredSpeed = preferredSpeed
        self.notes = notes
        self.dateAdded = dateAdded
        self.orderIndex = orderIndex
        self.clip = clip
    }

    var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }

    static func == (lhs: ClipSegment, rhs: ClipSegment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
