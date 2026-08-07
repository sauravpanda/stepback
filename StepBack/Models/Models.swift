import Foundation
import SwiftData

// These live models are the V2 schema shape (see Schema.swift). CloudKit
// sync imposes three rules on every model here: no unique constraints,
// every attribute optional or defaulted, every relationship optional.
// The optional relationship arrays sit behind non-optional computed
// accessors so call sites never deal with `[ClipSegment]?`.

@Model
final class DanceClip: Equatable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var assetIdentifier: String = ""
    var dateAdded: Date = Date()
    var eventName: String?
    var notes: String = ""
    var thumbnailData: Data?
    var durationSeconds: Double = 0

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

    /// Filename (in `OriginalStorage.directory`) for a sandboxed copy of the
    /// imported video. Only set when the "keep local copies" setting is on;
    /// nil clips resolve through the PHAsset reference instead.
    var originalFileName: String?

    /// `PHCloudIdentifier` string for the source asset. Unlike
    /// `assetIdentifier` (a device-local `PHAsset` identifier), this one is
    /// stable across iCloud Photo Library resyncs and app reinstalls, so a
    /// stale local identifier can be re-mapped instead of losing the clip.
    var cloudAssetIdentifier: String?

    @Relationship(deleteRule: .cascade, originalName: "segments", inverse: \ClipSegment.clip)
    var segmentsStorage: [ClipSegment]?

    @Relationship(originalName: "tags")
    var tagsStorage: [Tag]?

    var segments: [ClipSegment] {
        get { segmentsStorage ?? [] }
        set { segmentsStorage = newValue }
    }

    var tags: [Tag] {
        get { tagsStorage ?? [] }
        set { tagsStorage = newValue }
    }

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

    /// Resolved sandbox URL for the imported original copy, when one exists.
    var originalFileURL: URL? {
        guard let originalFileName else { return nil }
        return OriginalStorage.fileURL(name: originalFileName)
    }

    /// Best local file to play back: trim if present, otherwise the
    /// sandboxed original. Falls through to nil for reference-only clips,
    /// which the caller resolves via `PhotosService`.
    var preferredLocalFileURL: URL? {
        trimmedFileURL ?? originalFileURL
    }
}

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = ""

    @Relationship(originalName: "clips", inverse: \DanceClip.tagsStorage)
    var clipsStorage: [DanceClip]?

    var clips: [DanceClip] {
        get { clipsStorage ?? [] }
        set { clipsStorage = newValue }
    }

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

@Model
final class ClipSegment: Equatable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var startSeconds: Double = 0
    var endSeconds: Double = 0
    var preferredSpeed: Double = 1.0
    var notes: String = ""
    var dateAdded: Date = Date()
    var orderIndex: Int = 0
    var thumbnailData: Data?
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
