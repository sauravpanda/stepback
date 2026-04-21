# StepBack

A practice tool for learning dance from your own video library. iOS only, SwiftUI.

Slow footage down without pitch-shifting the audio, loop hard sections, frame-step through tricky moves, tag clips by event, compare yourself against the instructor side-by-side, and — critically — check whether your stepping actually lands on the beat.

> Primary user: the author. Daily-use quality, not App-Store-polish. No accounts, no backend, no cloud sync in v1.

## Why this exists

Apple's stock Photos/Videos tools can't do tight A/B loops, pitch-preserved slow-mo, or beat-locked step timing. Existing dance apps either don't combine these or lock them behind subscriptions and sync. StepBack does the one specific thing it needs to do, on-device, with nothing but Apple's SDKs.

## Features

**v1 — core practice loop**
- Import videos from Photos (multi-select, no copies — references `PHAsset` identifiers)
- Auto-group clips into events by creation date (24h gap = new event)
- Variable-speed playback (0.25×–1.5×) with pitch preservation
- A/B loop with draggable region, saved as named markers with preferred speed
- True frame-by-frame stepping (`AVPlayerItem.step(byCount:)`)
- Mirror mode
- Side-by-side compare view with synced playback

**v1.5 — beat detection**
- On-device BPM detection via STFT + autocorrelation (Accelerate / vDSP)
- Beat ticks on the scrubber, live count-in-measure indicator
- User-driven downbeat anchoring ("tap on beat 1"), persisted per clip
- Step-timing mode: tap every step, see ms-precise offset from nearest beat as a colored histogram

**v2 — later**
Pose tracking overlay (Vision), speed ramps, ghost overlay recording, iCloud sync. See the [roadmap](https://github.com/sauravpanda/stepback/issues).

## Tech

- SwiftUI + SwiftData (iOS 17+)
- AVKit / AVFoundation for playback and frame stepping
- PhotoKit for library access (no video copies)
- Vision for pose tracking (v2)
- Accelerate (vDSP) for FFT-based beat detection
- **Zero third-party dependencies.**

## Project structure

```
StepBack/
  StepBackApp.swift              @main, SwiftData container
  Models/Models.swift            DanceClip, Tag, LoopMarker
  Views/
    LibraryView.swift            Grid of clips, tag filter, import
    PracticeView.swift           The core player screen
    CompareView.swift            Side-by-side synced playback
  Services/
    PhotosService.swift          PHAsset -> AVURLAsset, thumbnails
    AutoTagService.swift         Cluster clips by time -> events
    PracticePlayerViewModel.swift Playback state, loop, speed, step timing
    BeatDetector.swift           Onset envelope + tempo autocorrelation
    AIServices.swift             Pose tracking stubs (v2)
  Utilities/Theme.swift          Colors, design tokens
```

## Building

1. Open `StepBack.xcodeproj` in Xcode 15+
2. Signing & Capabilities → pick your Apple ID team
3. Cmd+R with your iPhone plugged in

Free Apple ID signing: sideloaded apps expire in 7 days; re-run from Xcode to refresh.

See [BUILD.md](docs/BUILD.md) for details.

## Design tokens

Dark UI, hot-pink accent. No generic AI-gray look.

- `bg #0A0A0F` · `surface #171720` · `surfaceElevated #22222C`
- `accent #FF3B7F` · `accentSoft` = accent @ 15% alpha
- Speed pill colors: cyan <0.5×, green <1×, white =1×, orange >1×
- SF Rounded for display, SF Pro for body, SF Mono for timestamps

## Status

Pre-v1. Tracking progress via [issues](https://github.com/sauravpanda/stepback/issues) and [milestones](https://github.com/sauravpanda/stepback/milestones).

## License

MIT — see [LICENSE](LICENSE).
