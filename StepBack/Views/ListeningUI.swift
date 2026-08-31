import SwiftUI
import UIKit

// MARK: - Exercise picker

struct ExercisePicker: View {
    let selected: ListeningExercise
    let onSelect: (ListeningExercise) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ListeningExercise.allCases) { exercise in
                let isSelected = exercise == selected
                Button {
                    onSelect(exercise)
                } label: {
                    Label(exercise.title, systemImage: exercise.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Theme.Color.accent : Theme.Color.surfaceElevated)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(exercise.title)
            }
        }
    }
}

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

// MARK: - Phrase ribbon

enum PhraseSlotState: Equatable {
    case pending
    case hit
    case missed
}

/// One cell per phrase in the take, filling in as the drill runs. Gives the
/// dancer a sense of how far through they are and where they dropped the
/// count, without having to wait for the results card.
struct PhraseRibbon: View {
    let states: [PhraseSlotState]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: state))
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for state: PhraseSlotState) -> Color {
        switch state {
        case .pending: Theme.Color.surfaceElevated
        case .hit: Theme.Color.speedGreen
        case .missed: Color(hex: 0xFF5F5F)
        }
    }
}

// MARK: - Tap target

/// Full-width pad. Timing drills live or die on the tap being effortless
/// and unambiguous, so this is deliberately huge and fires a haptic on
/// contact — the same feedback PracticeView uses for beat-1 anchoring.
struct BigTapTarget: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool
    let onTap: () -> Void

    @State private var flash: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
            withAnimation(.easeOut(duration: 0.06)) { flash = true }
            withAnimation(.easeIn(duration: 0.2).delay(0.06)) { flash = false }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(isEnabled ? .black : Theme.Color.textTertiary)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(isEnabled ? .black.opacity(0.7) : Theme.Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var background: Color {
        guard isEnabled else { return Theme.Color.surfaceElevated }
        return flash ? Theme.Color.speedGreen : Theme.Color.accent
    }
}

// MARK: - Results

struct DrillResultsCard: View {
    let score: PhraseScore
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int((score.accuracy * 100).rounded()))%")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
                Text("accurate")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Button("Again", action: onRetry)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }

            HStack(spacing: 8) {
                CountBadge(label: "Caught", value: score.hits, tint: Theme.Color.speedGreen)
                CountBadge(label: "Missed", value: score.misses, tint: Color(hex: 0xFF5F5F))
                CountBadge(
                    label: "Stray",
                    value: score.falsePositives,
                    tint: Color(hex: 0xFFD93B)
                )
            }

            if let average = score.averageOffsetMs {
                Text(timingSummary(average))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding(14)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    /// Sign is the coaching cue: a consistent bias is a fixable habit,
    /// whereas noise around zero just means the count is loose.
    private func timingSummary(_ average: Double) -> String {
        let magnitude = Int(abs(average).rounded())
        if magnitude < 25 {
            return "Dead on the phrase — average \(magnitude)ms off."
        }
        return average < 0
            ? "Running early by \(magnitude)ms on average."
            : "Running late by \(magnitude)ms on average."
    }
}

private struct CountBadge: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Find the One result

struct FindTheOneCard: View {
    let result: FindTheOneResult
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(headline, systemImage: result.landedOnOne ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(result.landedOnOne ? Theme.Color.speedGreen : Color(hex: 0xFF5F5F))
                Spacer()
                Button("Again", action: onRetry)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(14)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    private var headline: String {
        result.landedOnOne ? "That was the one" : "Not the one"
    }

    private var detail: String {
        let magnitude = Int(abs(result.offsetMs).rounded())
        let direction = result.offsetMs < 0 ? "early" : "late"
        let timing = "\(result.rating.label) — \(magnitude)ms \(direction) of the nearest beat."
        guard !result.landedOnOne else { return timing }
        guard let position = result.measurePosition else { return timing }
        return "You landed on count \(position). " + timing
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
