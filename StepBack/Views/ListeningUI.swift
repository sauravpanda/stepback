import SwiftUI
import UIKit

// MARK: - Phrase counter

/// The big count readout. `isRevealed` is what makes Count It Out work —
/// the drill hides the number and the dancer has to keep the count
/// internally, so the view still knows the position but refuses to show it.
struct PhraseCounter: View {
    let position: Int?
    /// What to say on this slot — the beat number on the beat itself, or
    /// "e" / "&" / "a" / "trip" / "let" between beats.
    let spoken: String?
    let phraseLength: Int
    let isRevealed: Bool
    let pulseID: Int

    @State private var scale: CGFloat = 1.0

    /// Fixed so the block never changes height. The counter redraws every
    /// frame while playing, and anything with a variable intrinsic size here
    /// shoves the whole screen around several times a second.
    private static let numberHeight: CGFloat = 84
    private static let captionHeight: CGFloat = 16

    /// True on the "e", "&" and "a". Distinguished by colour rather than by
    /// size — a smaller font would change the line's height and move
    /// everything below it.
    private var isOffBeat: Bool {
        guard let spoken, let position else { return false }
        return spoken != "\(position)"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(display)
                .font(.system(size: 76, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .scaleEffect(scale)
                .frame(height: Self.numberHeight)
                .frame(maxWidth: .infinity)
            Text(caption)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(height: Self.captionHeight)
        }
        .onChange(of: pulseID) { _, _ in
            withAnimation(.easeOut(duration: 0.05)) { scale = 1.1 }
            withAnimation(.easeIn(duration: 0.18).delay(0.05)) { scale = 1.0 }
        }
    }

    private var numberColor: Color {
        guard isRevealed else { return Theme.Color.textTertiary }
        return isOffBeat ? Theme.Color.textSecondary : Theme.Color.textPrimary
    }

    private var display: String {
        guard isRevealed, let position else { return "–" }
        return spoken ?? "\(position)"
    }

    /// On a beat the big text *is* the number, so the caption only supplies
    /// the total. On a subdivision the number has been displaced by "e" or
    /// "&", so the caption carries it instead — otherwise "e of 8" reads as
    /// nonsense.
    private var caption: String {
        guard isRevealed else { return "counting blind" }
        guard isOffBeat, let position else { return "of \(phraseLength)" }
        return "\(position) of \(phraseLength)"
    }
}

// MARK: - Count row

/// The whole 8-count on one line, each beat broken into its subdivisions.
///
/// A measure of four dots only ever showed a quarter of the phrase, which is
/// the wrong unit for dancers — the 8 is what gets counted out loud. Every
/// beat carries a large dot and its subdivisions carry smaller ones, so
/// "1 e & a" is legible as shape as well as text.
struct CountRow: View {
    let beatsPerRow: Int
    let subdivision: CountSubdivision
    /// 1-based position within the row.
    let currentBeat: Int?
    /// 0-based slot inside the current beat.
    let currentSlot: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            ForEach(1...max(1, beatsPerRow), id: \.self) { beat in
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach(0..<subdivision.perBeat, id: \.self) { slot in
                            Circle()
                                .fill(fill(beat: beat, slot: slot))
                                .frame(width: size(slot), height: size(slot))
                        }
                    }
                    .frame(height: 10)
                    Text("\(beat)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            beat == currentBeat
                                ? Theme.Color.textSecondary
                                : Theme.Color.textTertiary.opacity(0.5)
                        )
                }
            }
        }
        .animation(.easeOut(duration: 0.06), value: currentBeat)
        .animation(.easeOut(duration: 0.06), value: currentSlot)
    }

    private func size(_ slot: Int) -> CGFloat {
        slot == 0 ? 9 : 5
    }

    private func fill(beat: Int, slot: Int) -> Color {
        guard beat == currentBeat, slot == currentSlot else {
            return Theme.Color.surfaceElevated
        }
        // Beat 1 of the 8 is the landmark, so it lights in the accent.
        return beat == 1 && slot == 0 ? Theme.Color.accent : Theme.Color.textPrimary
    }
}

// MARK: - Transport

/// Phrase-relative transport. The skip buttons move by musical structure
/// rather than by a fixed number of seconds, because "back one phrase" is
/// what a dancer actually wants and "back 15 seconds" never lands anywhere
/// useful.
struct PhraseTransport: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let onPrevious: () -> Void
    let onTogglePlay: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            TransportButton(
                systemName: "backward.end.fill",
                size: 22,
                isEnabled: isEnabled,
                action: onPrevious
            )
            .accessibilityLabel("Previous phrase")

            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 62, height: 62)
                    .background(Theme.Color.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            TransportButton(
                systemName: "forward.end.fill",
                size: 22,
                isEnabled: isEnabled,
                action: onNext
            )
            .accessibilityLabel("Next phrase")
        }
    }
}

private struct TransportButton: View {
    let systemName: String
    let size: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.Color.textPrimary : Theme.Color.textTertiary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Anchor correction

/// Always-present correction for the auto-placed downbeat.
///
/// The anchor is a guess from kick energy and will sometimes sit a beat
/// off. Nudging is offered permanently rather than behind a setup step, so
/// a wrong count costs one tap instead of a trip through a settings screen.
struct AnchorNudgeBar: View {
    let hasAnchor: Bool
    let onShift: (Int) -> Void
    let onTapBeatOne: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(hasAnchor ? "Count off?" : "No count yet")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
            if hasAnchor {
                NudgeButton(systemName: "arrow.left") { onShift(-1) }
                    .accessibilityLabel("Shift beat 1 back")
                NudgeButton(systemName: "arrow.right") { onShift(1) }
                    .accessibilityLabel("Shift beat 1 forward")
            }
            Spacer()
            Button(action: onTapBeatOne) {
                Label("Tap on 1", systemImage: "hand.tap")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct NudgeButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 28, height: 24)
                .background(Theme.Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toggles

struct PlayerToggleChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isOn ? Theme.Color.accent : Theme.Color.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var foreground: Color {
        if !isEnabled { return Theme.Color.textTertiary }
        return isOn ? .black : Theme.Color.textSecondary
    }
}

// MARK: - Analysis banner

/// Shown while the beat grid is still being computed. Playback is never
/// blocked on analysis, so this reports progress rather than gating.
struct AnalyzingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().tint(Theme.Color.accent)
            Text("Finding the beat…")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

// MARK: - Subdivision picker

/// Chooses how finely the count is spoken and clicked.
struct SubdivisionMenu: View {
    let selection: CountSubdivision
    let onSelect: (CountSubdivision) -> Void

    var body: some View {
        Menu {
            Picker("Count", selection: binding) {
                ForEach(CountSubdivision.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.Color.surfaceElevated, in: Capsule())
        }
    }

    private var binding: Binding<CountSubdivision> {
        Binding(get: { selection }, set: onSelect)
    }
}
