# Contributing

StepBack is a personal-scratch tool that happens to be open source. Contributions are welcome, but the bar for what lands is "does it help the author practice West Coast Swing." That's the north star.

## Ground rules

- **No third-party dependencies.** Apple SDKs only. PRs that add SwiftPM/CocoaPods/Carthage packages will be closed.
- **iOS 17+** only. SwiftData is required.
- **On-device only.** No analytics, no accounts, no cloud calls in v1/v1.5. (Phase 2 may add an optional smart-naming feature; that will be explicit and opt-in.)
- **Dark theme, hot-pink accent.** See `Theme.swift`. Don't introduce new color tokens without discussion.

## Dev setup

1. Xcode 15.4+
2. `brew install swiftlint xcodegen` (both enforced by CI)
3. Open `StepBack.xcodeproj` — if you change the target structure, edit `project.yml` and run `xcodegen generate`
4. Cmd+R on a device. Simulator works for layout, but AVFoundation behavior (pitch preservation, frame stepping) must be verified on hardware.

See [docs/BUILD.md](docs/BUILD.md) for signing and provisioning notes.

## Workflow

1. Pick an issue from the [roadmap](https://github.com/sauravpanda/stepback/issues) — preferably one tagged `good first issue` if you're new
2. Branch off `main`: `git checkout -b <short-slug>`
3. Keep PRs focused — one feature or one fix per PR
4. Run SwiftLint locally before pushing: `swiftlint lint --strict`
5. Open a PR against `main` — fill in the template
6. Verify on a real device and paste a short screen recording for UI changes

## Commit style

- Present-tense, imperative: "Add loop markers", not "Added" or "Adds"
- Reference issues in the body: `Closes #12`
- Keep subject under 72 chars

## Code style

- Stick to `swift-format` defaults; SwiftLint config in `.swiftlint.yml` is the source of truth for rules
- `[weak self]` in every periodic time observer closure
- Never `try!` or force-unwrap outside of `#Preview` code
- `@MainActor` anything that touches `@Published` / observable state
- `Task { @MainActor in … }` after background work completes

## Testing

- Unit tests for `BeatDetector` against fixture audio (to be added — see #TBD)
- UI and playback changes: verify on hardware, document test clips used in the PR

## Filing issues

- **Bug**: use the bug template, include device + iOS version + steps
- **Feature**: use the feature template, say why it beats the current behavior for practice
- If you're unsure whether something belongs, open a "Discussion" issue first

## License

By contributing you agree your changes will be released under the [MIT license](LICENSE).
