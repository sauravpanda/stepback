import SwiftData
import SwiftUI

@main
struct StepBackApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [DanceClip.self, Tag.self, LoopMarker.self])
    }
}
