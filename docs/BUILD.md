# Building StepBack

## Requirements

- Xcode 15.4+
- iOS 17+ device or simulator (SwiftData)
- Apple ID (free signing works for personal use)

## First-time setup

1. Open `StepBack.xcodeproj` in Xcode
2. Select the `StepBack` target → **Signing & Capabilities**
   - Check **Automatically manage signing**
   - **Team**: your Apple ID
   - **Bundle Identifier**: change to something unique, e.g. `com.yourname.stepback`
3. Plug in your iPhone
4. Select your device in the run destination
5. Cmd+R

On the phone, the first time: **Settings → General → VPN & Device Management → trust your dev account.**

## Info.plist keys

The target bundles these usage descriptions:

| Key | Reason |
|---|---|
| `NSPhotoLibraryUsageDescription` | Read videos from Photos for practice playback |
| `NSPhotoLibraryAddUsageDescription` | (Phase 2) Save ghost-overlay recordings back to Photos |
| `NSCameraUsageDescription` | (Phase 2) Ghost-overlay recording |
| `NSMicrophoneUsageDescription` | (Phase 2) Audio during ghost-overlay recording |

## Signing gotchas

- **Free signing expires every 7 days.** Re-plug your phone and hit Cmd+R to refresh.
- Free accounts are limited to **3 sideloaded apps per device** and **10 App IDs per week.** Don't churn bundle identifiers.
- A paid Apple Developer account ($99/yr) lifts both limits.

## CI

`.github/workflows/ci.yml` runs on every push and PR:

- **SwiftLint** (`--strict`)
- **xcodebuild** build + test on `iPhone 15` simulator, iOS latest

The build step is guarded: until the Xcode project is committed, the job no-ops so CI stays green during initial scaffolding.

## Test clips

For development, keep a handful of short (10–30s) clips in your Photos library covering:

- Well-defined drums (for beat detection sanity)
- Swing/blues with syncopation (tests half-time/double-time fallback)
- Low-volume or phone-mic-quality audio (realistic event footage)
