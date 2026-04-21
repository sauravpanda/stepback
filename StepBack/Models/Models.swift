import Foundation
import SwiftData

@Model
final class DanceClip {
    var id: UUID
    var title: String
    var assetIdentifier: String
    var dateAdded: Date
    var eventName: String?
    var notes: String
    var thumbnailData: Data?
    var durationSeconds: Double

    @Relationship(deleteRule: .cascade, inverse: \LoopMarker.clip)
    var loopMarkers: [LoopMarker] = []

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
