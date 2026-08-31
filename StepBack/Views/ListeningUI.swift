import SwiftUI
import UIKit

// MARK: - Readiness badge

struct ReadinessBadge: View {
    let readiness: ListeningReadiness

    var body: some View {
        Label(readiness.label, systemImage: readiness.systemImage)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private var tint: Color {
        switch readiness {
        case .ready: Theme.Color.speedGreen
        case .needsAnchor, .needsBeats: Theme.Color.textTertiary
        }
    }
}

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
    let phraseLength: Int
    let isRevealed: Bool
    let pulseID: Int

    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 2) {
            Text(display)
                .font(.system(size: 76, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isRevealed ? Theme.Color.textPrimary : Theme.Color.textTertiary)
                .scaleEffect(scale)
            Text(isRevealed ? "of \(phraseLength)" : "counting blind")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .onChange(of: pulseID) { _, _ in
            withAnimation(.easeOut(duration: 0.05)) { scale = 1.1 }
            withAnimation(.easeIn(duration: 0.18).delay(0.05)) { scale = 1.0 }
        }
    }

    private var display: String {
        guard isRevealed, let position else { return "–" }
        return "\(position)"
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

// MARK: - Transport

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.Color.surfaceElevated, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup

/// Walks an unready clip through the two prerequisites the drills need: a
/// beat grid, then a placed beat 1. Detection itself is driven by the
/// `BPMBadge` in the screen header, so this card only carries the
/// explanation and the anchoring controls.
struct ListeningSetupCard: View {
    let readiness: ListeningReadiness
    let isPlaying: Bool
    let onTogglePlay: () -> Void
    let onTapBeatOne: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(instruction)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            if readiness == .needsAnchor {
                HStack(spacing: 12) {
                    PlayPauseButton(isPlaying: isPlaying, action: onTogglePlay)
                    DownbeatAnchorBar(
                        hasAnchor: false,
                        onTap: onTapBeatOne,
                        onClear: {}
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    private var instruction: String {
        switch readiness {
        case .needsBeats:
            "Detect the beat grid first — every drill here is derived from it."
        case .needsAnchor:
            "Play the clip and tap the moment you hear beat 1. That single anchor defines every phrase boundary in the song."
        case .ready:
            ""
        }
    }
}
