import AVFoundation
import SwiftData
import SwiftUI

@main
struct StepBackApp: App {
    init() {
        // Route playback through .playback so video audio ignores the silent
        // switch — otherwise the phone's ringer toggle mutes practice clips.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [DanceClip.self, Tag.self, LoopMarker.self])
    }
}
