import AVFoundation
import SwiftData
import SwiftUI

@main
struct StepBackApp: App {

    private let container: ModelContainer

    init() {
        // Route playback through .playback so video audio ignores the silent
        // switch — otherwise the phone's ringer toggle mutes practice clips.
        // Dispatched off-actor: setActive does IPC that trips the runtime's
        // unsafeForcedSync diagnostic when invoked from App.init on MainActor.
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }

        Self.ensureStoreDirectoryExists()

        let schema = Schema(versionedSchema: SchemaV3.self)
        do {
            // `cloudKitDatabase: .automatic` — syncs through the app's iCloud
            // container when the entitlement is present (paid developer
            // account with the iCloud capability enabled), and behaves as a
            // plain local store when it isn't. The models are shaped to
            // CloudKit's rules either way, so flipping the capability on is
            // all it takes to turn syncing on.
            container = try ModelContainer(
                for: schema,
                migrationPlan: StepBackMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            )
        } catch {
            do {
                // CloudKit setup can fail independently of the local store
                // (mis-provisioned container, sync validation). Local-only
                // beats crashing out of practice.
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: StepBackMigrationPlan.self,
                    configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                )
            } catch {
                // For a personal-use app, surfacing this as a hard crash beats
                // silently corrupting the store. If the migration plan ever
                // fails on a real device, recovery is "delete app, reinstall."
                fatalError("Failed to create StepBack ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }

    /// SwiftData keeps its store at `Library/Application Support/default.store`,
    /// and on a fresh install that folder does not exist. CoreData copes —
    /// it fails to create the file, logs a diagnostic of every directory up
    /// to `/` ("Sandbox access to file-write-create denied", errno 2), then
    /// makes the folder and retries successfully — but several hundred lines
    /// of that on first launch read like a broken install. Creating the
    /// folder first skips the whole detour.
    private static func ensureStoreDirectoryExists() {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
