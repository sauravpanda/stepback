import Foundation
import SwiftData

/// Versioned schema baseline for StepBack's SwiftData store.
///
/// V1 is the original on-disk shape, frozen below as nested model copies.
/// There is intentionally no V0 covering the pre-`LoopMarker`-removal era:
/// that change shipped as an accepted solo-tester data loss (see commit
/// `8a11bdb`), so a backwards-looking migration would only recover data
/// nobody has.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SchemaV1.DanceClip.self, SchemaV1.Tag.self, SchemaV1.ClipSegment.self]
    }

    // Frozen copies of every model as it existed at V1 — not the live
    // classes. SwiftData rejects two versioned schemas that share model
    // types with a "checksum while model is still editable" error, and a
    // faithful frozen shape is what makes the V1→V2 diff computable.

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

        var bpm: Double?
        var beatTimesData: Data?
        var firstDownbeatSeconds: Double?
        var beatsPerMeasure: Int = 4

        var trimmedFileName: String?
        var originalFileName: String?

        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.ClipSegment.clip)
        var segments: [SchemaV1.ClipSegment] = []

        var tags: [SchemaV1.Tag] = []

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

        @Relationship(inverse: \SchemaV1.DanceClip.tags)
        var clips: [SchemaV1.DanceClip] = []

        init(id: UUID = UUID(), name: String, colorHex: String) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
        }
    }

    @Model
    final class ClipSegment {
        var id: UUID
        var title: String
        var startSeconds: Double
        var endSeconds: Double
        var preferredSpeed: Double
        var notes: String
        var dateAdded: Date
        var orderIndex: Int
        var thumbnailData: Data?
        var clip: SchemaV1.DanceClip?

        init(
            id: UUID = UUID(),
            title: String,
            startSeconds: Double,
            endSeconds: Double,
            preferredSpeed: Double = 1.0,
            notes: String = "",
            dateAdded: Date = Date(),
            orderIndex: Int = 0,
            clip: SchemaV1.DanceClip? = nil
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
    }
}

/// V2 — frozen below. Three changes from V1:
///
/// 1. `DanceClip.cloudAssetIdentifier` (new, optional) stores the
///    `PHCloudIdentifier` so stale local Photos identifiers can be healed.
/// 2. Every relationship became optional storage (`segmentsStorage`,
///    `tagsStorage`, `clipsStorage`, renamed via `originalName` so
///    lightweight migration carries the rows over) and every attribute
///    gained a default — both hard requirements for CloudKit sync.
/// 3. No unique constraints (V1 had none either; CloudKit forbids them).
enum SchemaV2: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SchemaV2.DanceClip.self, SchemaV2.Tag.self, SchemaV2.ClipSegment.self]
    }

    // Frozen copies of the V2 shape — `Models.swift` as it stood before
    // `isFavorite` — kept faithful down to the `originalName` renames, which
    // are part of how the store lines these entities up with V1's.

    @Model
    final class DanceClip {
        var id: UUID = UUID()
        var title: String = ""
        var assetIdentifier: String = ""
        var dateAdded: Date = Date()
        var eventName: String?
        var notes: String = ""
        var thumbnailData: Data?
        var durationSeconds: Double = 0

        var bpm: Double?
        var beatTimesData: Data?
        var firstDownbeatSeconds: Double?
        var beatsPerMeasure: Int = 4

        var trimmedFileName: String?
        var originalFileName: String?
        var cloudAssetIdentifier: String?

        @Relationship(deleteRule: .cascade, originalName: "segments", inverse: \SchemaV2.ClipSegment.clip)
        var segmentsStorage: [SchemaV2.ClipSegment]?

        @Relationship(originalName: "tags")
        var tagsStorage: [SchemaV2.Tag]?

        init(id: UUID = UUID(), title: String, assetIdentifier: String) {
            self.id = id
            self.title = title
            self.assetIdentifier = assetIdentifier
        }
    }

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = ""

        @Relationship(originalName: "clips", inverse: \SchemaV2.DanceClip.tagsStorage)
        var clipsStorage: [SchemaV2.DanceClip]?

        init(id: UUID = UUID(), name: String, colorHex: String) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
        }
    }

    @Model
    final class ClipSegment {
        var id: UUID = UUID()
        var title: String = ""
        var startSeconds: Double = 0
        var endSeconds: Double = 0
        var preferredSpeed: Double = 1.0
        var notes: String = ""
        var dateAdded: Date = Date()
        var orderIndex: Int = 0
        var thumbnailData: Data?
        var clip: SchemaV2.DanceClip?

        init(
            id: UUID = UUID(),
            title: String,
            startSeconds: Double,
            endSeconds: Double,
            clip: SchemaV2.DanceClip? = nil
        ) {
            self.id = id
            self.title = title
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
            self.clip = clip
        }
    }
}

/// V3 — the current live models in `Models.swift`. One change from V2:
/// `DanceClip.isFavorite`, a `Bool` defaulting to false, behind the
/// Library's Favorites collection. Defaulted rather than optional so
/// CloudKit is happy and every existing row reads as "not yet".
enum SchemaV3: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [DanceClip.self, Tag.self, ClipSegment.self]
    }
}

/// SwiftData migration plan for StepBack.
///
/// Both stages are lightweight. V1 → V2: additive optional column,
/// relationship renames declared through `originalName`, optionality
/// loosening. V2 → V3: one additive defaulted column. Nothing that needs a
/// custom stage.
enum StepBackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )
}
