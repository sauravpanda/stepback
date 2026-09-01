import SwiftUI
import UIKit

// Components specific to the ear-training drills. Separated from the player
// chrome in `ListeningUI` so neither file outgrows SwiftLint's length limit
// and each stays about one thing.

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

// MARK: - Drill panel

/// The ear-training panel that folds out below the player.
///
/// A self-contained component rather than a slice of `ListeningPlayerView`:
/// it needs no access to the player's private state, only to the run it is
/// displaying and the handful of callbacks that drive it.
struct DrillPanel: View {
    let exercise: ListeningExercise
    let run: ListeningDrillState
    let slotStates: [PhraseSlotState]
    @Binding var revealPhrases: Int
    let onSelectExercise: (ListeningExercise) -> Void
    let onStart: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(Theme.Color.divider)
            ExercisePicker(selected: exercise, onSelect: onSelectExercise)
            Text(exercise.blurb)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            if exercise == .countItOut, run.phase == .idle {
                Stepper(value: $revealPhrases, in: 1...4) {
                    Text("Counter visible for \(revealPhrases) × 8")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .tint(Theme.Color.accent)
            }
            if run.plan != nil, run.phase != .idle {
                PhraseRibbon(states: slotStates)
            }
            tapTarget
            if let planError = run.planError {
                Text(planError)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Color(hex: 0xFF5F5F))
            }
            results
        }
    }

    @ViewBuilder
    private var tapTarget: some View {
        if run.phase == .running {
            BigTapTarget(
                title: "Tap",
                subtitle: exercise == .findTheOne ? "on beat 1" : "on every 1 of the phrase",
                isEnabled: true,
                onTap: onTap
            )
        } else {
            BigTapTarget(
                title: run.phase == .finished ? "Go again" : "Start",
                subtitle: exercise.title,
                isEnabled: true,
                onTap: onStart
            )
        }
    }

    @ViewBuilder
    private var results: some View {
        if let oneShot = run.oneShot {
            FindTheOneCard(result: oneShot, onRetry: onStart)
        } else if let score = run.score {
            DrillResultsCard(score: score, onRetry: onStart)
        }
    }
}
