@testable import StepBack
import SwiftData
import XCTest

@MainActor
final class StepBackMigrationPlanTests: XCTestCase {

    // MARK: - Schema versions

    func testSchemaVersionIdentifiers() {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(SchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
    }

    func testSchemaV3ContainsExactlyTheCurrentLiveModels() {
        // The point of this test is to fail loudly when someone adds a new
        // @Model type without versioning it. New models should land as part
        // of a SchemaV4 + migration stage, not by quietly extending V3.
        let names = Set(SchemaV3.models.map { String(describing: $0) })
        XCTAssertEqual(names, ["DanceClip", "Tag", "ClipSegment"])
    }

    func testFrozenSchemasKeepTheirEntityNames() {
        // The frozen copies are nested types, but their entity names must
        // still match the live classes or migration can't line them up.
        for schema in [SchemaV1.self, SchemaV2.self] as [any VersionedSchema.Type] {
            let names = Set(schema.models.map { String(describing: $0) })
            XCTAssertEqual(names, ["DanceClip", "Tag", "ClipSegment"], "\(schema)")
        }
    }

    // MARK: - Migration plan

    func testMigrationPlanRegistersEverySchemaInOrder() {
        let names = StepBackMigrationPlan.schemas.map { String(describing: $0) }
        XCTAssertEqual(names, ["SchemaV1", "SchemaV2", "SchemaV3"])
    }

    func testMigrationPlanHasOneStagePerStep() {
        XCTAssertEqual(StepBackMigrationPlan.stages.count, 2)
    }

    // MARK: - End-to-end container construction

    func testContainerOpensWithMigrationPlan() throws {
        // Smoke test: a fresh in-memory container should construct cleanly
        // when we route through SchemaV3 + StepBackMigrationPlan, and should
        // accept inserts of every live model type.
        let schema = Schema(versionedSchema: SchemaV3.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: StepBackMigrationPlan.self,
            configurations: config
        )

        let context = ModelContext(container)
        let clip = DanceClip(title: "Test", assetIdentifier: "ASSET-MIG")
        let tag = Tag(name: "tag", colorHex: "#FFFFFF")
        let segment = ClipSegment(title: "Seg", startSeconds: 0, endSeconds: 1, clip: clip)
        context.insert(clip)
        context.insert(tag)
        context.insert(segment)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DanceClip>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Tag>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClipSegment>()), 1)
        XCTAssertFalse(clip.isFavorite, "a new clip is not a favourite until the user says so")
    }

    // MARK: - Stored migrations

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stepback-migration-\(UUID().uuidString).store")
    }

    /// Reopens `storeURL` at the current schema through the migration plan
    /// and returns the one clip it should contain.
    private func migratedClip(at storeURL: URL) throws -> DanceClip {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: StepBackMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: storeURL)
        )
        let clips = try ModelContext(container).fetch(FetchDescriptor<DanceClip>())
        XCTAssertEqual(clips.count, 1)
        return try XCTUnwrap(clips.first)
    }

    func testV1StoreMigratesToCurrentPreservingDataAndRelationships() throws {
        // The V2 relationships were renamed to *Storage props (with
        // `originalName` pointing back). This is the test that proves an
        // existing V1 store carries its rows and links through that rename
        // and on through V3.
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try autoreleasepool {
            let schemaV1 = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(
                for: schemaV1,
                configurations: ModelConfiguration(schema: schemaV1, url: storeURL)
            )
            let context = ModelContext(container)
            let clip = SchemaV1.DanceClip(title: "Legacy", assetIdentifier: "ASSET-V1")
            clip.originalFileName = "legacy.mov"
            let segment = SchemaV1.ClipSegment(title: "Basic", startSeconds: 1, endSeconds: 2, clip: clip)
            let tag = SchemaV1.Tag(name: "Event", colorHex: "#FF3B7F")
            clip.tags.append(tag)
            context.insert(clip)
            context.insert(segment)
            context.insert(tag)
            try context.save()
        }

        let clip = try migratedClip(at: storeURL)
        XCTAssertEqual(clip.title, "Legacy")
        XCTAssertEqual(clip.assetIdentifier, "ASSET-V1")
        XCTAssertEqual(clip.originalFileName, "legacy.mov")
        XCTAssertNil(clip.cloudAssetIdentifier, "New V2 column starts empty")
        XCTAssertFalse(clip.isFavorite, "New V3 column starts false")
        XCTAssertEqual(clip.segments.count, 1)
        XCTAssertEqual(clip.segments.first?.title, "Basic")
        XCTAssertEqual(clip.tags.count, 1)
        XCTAssertEqual(clip.tags.first?.name, "Event")
    }

    func testV2StoreMigratesToCurrentPreservingDataAndRelationships() throws {
        // Every phone that ran the app between V2 and V3 has one of these.
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try autoreleasepool {
            let schemaV2 = Schema(versionedSchema: SchemaV2.self)
            let container = try ModelContainer(
                for: schemaV2,
                configurations: ModelConfiguration(schema: schemaV2, url: storeURL)
            )
            let context = ModelContext(container)
            let clip = SchemaV2.DanceClip(title: "Recent", assetIdentifier: "ASSET-V2")
            clip.cloudAssetIdentifier = "CLOUD-V2"
            clip.bpm = 118
            let segment = SchemaV2.ClipSegment(title: "Whip", startSeconds: 3, endSeconds: 5, clip: clip)
            let tag = SchemaV2.Tag(name: "Blues", colorHex: "#5FE7FF")
            clip.tagsStorage = [tag]
            context.insert(clip)
            context.insert(segment)
            context.insert(tag)
            try context.save()
        }

        let clip = try migratedClip(at: storeURL)
        XCTAssertEqual(clip.title, "Recent")
        XCTAssertEqual(clip.cloudAssetIdentifier, "CLOUD-V2")
        XCTAssertEqual(clip.bpm, 118)
        XCTAssertFalse(clip.isFavorite, "New V3 column starts false")
        XCTAssertEqual(clip.segments.first?.title, "Whip")
        XCTAssertEqual(clip.tags.first?.name, "Blues")
    }
}
