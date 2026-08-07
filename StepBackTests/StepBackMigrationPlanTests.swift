@testable import StepBack
import SwiftData
import XCTest

@MainActor
final class StepBackMigrationPlanTests: XCTestCase {

    // MARK: - Schema versions

    func testSchemaVersionIdentifiers() {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
    }

    func testSchemaV2ContainsExactlyTheCurrentLiveModels() {
        // The point of this test is to fail loudly when someone adds a new
        // @Model type without versioning it. New models should land as part
        // of a SchemaV3 + migration stage, not by quietly extending V2.
        let names = Set(SchemaV2.models.map { String(describing: $0) })
        XCTAssertEqual(names, ["DanceClip", "Tag", "ClipSegment"])
    }

    func testSchemaV1FrozenModelsKeepTheirEntityNames() {
        // The frozen copies are nested types, but their entity names must
        // still match the live classes or migration can't line them up.
        let names = Set(SchemaV1.models.map { String(describing: $0) })
        XCTAssertEqual(names, ["DanceClip", "Tag", "ClipSegment"])
    }

    // MARK: - Migration plan

    func testMigrationPlanRegistersBothSchemas() {
        let names = StepBackMigrationPlan.schemas.map { String(describing: $0) }
        XCTAssertEqual(names, ["SchemaV1", "SchemaV2"])
    }

    func testMigrationPlanHasOneLightweightStage() {
        XCTAssertEqual(StepBackMigrationPlan.stages.count, 1)
    }

    // MARK: - End-to-end container construction

    func testContainerOpensWithMigrationPlan() throws {
        // Smoke test: a fresh in-memory container should construct cleanly
        // when we route through SchemaV2 + StepBackMigrationPlan, and should
        // accept inserts of every live model type.
        let schema = Schema(versionedSchema: SchemaV2.self)
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
    }

    // MARK: - V1 → V2 migration

    func testV1StoreMigratesToV2PreservingDataAndRelationships() throws {
        // The V2 relationships were renamed to *Storage props (with
        // `originalName` pointing back). This is the test that proves an
        // existing V1 store carries its rows and links through that rename.
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepback-migration-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
        }

        // Write a V1 store with one fully-linked object graph.
        try autoreleasepool {
            let schemaV1 = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(
                for: schemaV1,
                configurations: ModelConfiguration(schema: schemaV1, url: storeURL)
            )
            let context = ModelContext(container)
            let clip = SchemaV1.DanceClip(title: "Legacy", assetIdentifier: "ASSET-V1")
            clip.originalFileName = "legacy.mov"
            let segment = SchemaV1.ClipSegment(
                title: "Basic",
                startSeconds: 1,
                endSeconds: 2,
                clip: clip
            )
            let tag = SchemaV1.Tag(name: "Event", colorHex: "#FF3B7F")
            clip.tags.append(tag)
            context.insert(clip)
            context.insert(segment)
            context.insert(tag)
            try context.save()
        }

        // Reopen the same file through the migration plan at V2.
        let schemaV2 = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schemaV2,
            migrationPlan: StepBackMigrationPlan.self,
            configurations: ModelConfiguration(schema: schemaV2, url: storeURL)
        )
        let context = ModelContext(container)
        let clips = try context.fetch(FetchDescriptor<DanceClip>())

        XCTAssertEqual(clips.count, 1)
        let clip = try XCTUnwrap(clips.first)
        XCTAssertEqual(clip.title, "Legacy")
        XCTAssertEqual(clip.assetIdentifier, "ASSET-V1")
        XCTAssertEqual(clip.originalFileName, "legacy.mov")
        XCTAssertNil(clip.cloudAssetIdentifier, "New V2 column starts empty")
        XCTAssertEqual(clip.segments.count, 1)
        XCTAssertEqual(clip.segments.first?.title, "Basic")
        XCTAssertEqual(clip.tags.count, 1)
        XCTAssertEqual(clip.tags.first?.name, "Event")
    }
}
