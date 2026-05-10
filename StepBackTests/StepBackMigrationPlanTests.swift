@testable import StepBack
import SwiftData
import XCTest

@MainActor
final class StepBackMigrationPlanTests: XCTestCase {

    // MARK: - SchemaV1

    func testSchemaV1IsVersionOneZeroZero() {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }

    func testSchemaV1ContainsExactlyTheCurrentLiveModels() {
        // The point of this test is to fail loudly when someone adds a new
        // @Model type without versioning it. New models should land as part
        // of a SchemaV2 + migration stage, not by quietly extending V1.
        let names = Set(SchemaV1.models.map { String(describing: $0) })
        XCTAssertEqual(names, ["DanceClip", "Tag", "ClipSegment"])
    }

    // MARK: - Migration plan

    func testMigrationPlanRegistersOnlySchemaV1() {
        let names = StepBackMigrationPlan.schemas.map { String(describing: $0) }
        XCTAssertEqual(names, ["SchemaV1"])
    }

    func testMigrationPlanHasNoStagesForBaseline() {
        // V1 is the baseline; the first real stage lands with V2.
        XCTAssertTrue(StepBackMigrationPlan.stages.isEmpty)
    }

    // MARK: - End-to-end container construction

    func testContainerOpensWithMigrationPlan() throws {
        // Smoke test: a fresh in-memory container should construct cleanly
        // when we route through SchemaV1 + StepBackMigrationPlan, and should
        // accept inserts of every live model type.
        let schema = Schema(versionedSchema: SchemaV1.self)
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
}
