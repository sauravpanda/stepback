import Foundation
import SwiftData

/// Versioned schema baseline for StepBack's SwiftData store.
///
/// V1 is the *current* on-disk shape. There is intentionally no V0 covering
/// the pre-`LoopMarker`-removal era: that change shipped as an accepted
/// solo-tester data loss (see commit `8a11bdb`), so a backwards-looking
/// migration would only recover data nobody has. The value of declaring V1
/// now is forward-looking — when the next schema change lands (CloudKit
/// sync, on-disk thumbnails, new `ClipSegment` fields, etc.), it ships as a
/// V2 with an explicit `MigrationStage` between V1 and V2.
///
/// Authoring V2 correctly requires *frozen copies* of every model as it
/// existed at V1 (nested in this enum), not a second schema pointing at the
/// same live classes — SwiftData rejects two versioned schemas that share
/// model types with a "checksum while model is still editable" error.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [DanceClip.self, Tag.self, ClipSegment.self]
    }
}

/// SwiftData migration plan for StepBack.
///
/// Today this carries a single baseline (V1) with no stages — meaning any
/// existing on-device store is treated as already-V1 and opened with
/// SwiftData's lightweight migration. The plan is wired through
/// `ModelContainer` regardless so future versions slot in without having
/// to rewrite the container construction at the call site.
enum StepBackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
