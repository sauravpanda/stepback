import SwiftUI
import UIKit

// Components specific to the ear-training drills. Separated from the player
// chrome in `ListeningUI` so neither file outgrows SwiftLint's length limit
// and each stays about one thing.

/// Colours the drills share for the two ways a tap can go wrong.
enum DrillPalette {
    /// A target nobody tapped. Dimmed so it can't be confused with an
    /// `.off` hit, which uses `StepRating`'s full red.
    static let missed = Color(hex: 0xFF5F5F).opacity(0.35)
    /// A tap that landed on nothing.
    static let stray = Color(hex: 0xFFD93B)
    static let error = Color(hex: 0xFF5F5F)
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

// MARK: - Target ribbon

/// One cell per target in the take, filling in as the drill runs. Gives
/// the dancer a sense of how far through they are and where they dropped
/// the count, without having to wait for the results card. Hits are
/// coloured by how tight they were, so a run of yellow says "you're
/// catching it, but late" before the summary does.
struct PhraseRibbon: View {
    let states: [PhraseSlotState]

    var body: some View {
        HStack(spacing: states.count > 12 ? 2 : 4) {
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
        case .hit(let rating): rating.color
        case .missed: DrillPalette.missed
        }
    }
}

// MARK: - Live feedback

/// What the last tap earned, shown the instant it lands.
///
/// Motor timing learns from feedback inside a second; a percentage at the
/// end of eight phrases is a report, not a lesson. Fixed height so the
/// panel doesn't jump as the text changes.
struct TapFeedbackLabel: View {
    let feedback: TapFeedback?
    let exercise: ListeningExercise
    /// Changes with every tap, so identical feedback twice running still
    /// visibly registers as a new tap.
    let tapCount: Int

    @State private var scale: CGFloat = 1

    private static let height: CGFloat = 20

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .scaleEffect(scale)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
            .onChange(of: tapCount) { _, _ in
                withAnimation(.easeOut(duration: 0.05)) { scale = 1.12 }
                withAnimation(.easeIn(duration: 0.2).delay(0.05)) { scale = 1 }
            }
    }

    private var text: String {
        guard let feedback else {
            return exercise.gradesEveryBeat
                ? "Tap along — early or late shows here"
                : "Listening for your first 1…"
        }
        let magnitude = Int(abs(feedback.offsetMs).rounded())
        let side = feedback.offsetMs < 0 ? "early" : "late"
        guard feedback.isHit else {
            return "Stray — \(magnitude)ms \(side) of the nearest 1"
        }
        let timing = magnitude < 10 ? "dead on" : "\(magnitude)ms \(side)"
        return "\(feedback.rating.label) · \(timing)"
    }

    private var color: Color {
        guard let feedback else { return Theme.Color.textTertiary }
        return feedback.isHit ? feedback.rating.color : DrillPalette.error
    }
}

/// One haptic per tap, graded like the feedback: the lighter it feels, the
/// closer it landed. A stray tap gets the error buzz, which is unmistakable
/// even with eyes on the dance floor rather than the screen.
enum DrillHaptics {
    static func play(for feedback: TapFeedback?) {
        guard let feedback, feedback.isHit else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch feedback.rating {
        case .perfect: style = .light
        case .good: style = .medium
        case .off: style = .rigid
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Tap target

/// Full-width pad. Timing drills live or die on the tap being effortless
/// and unambiguous, so this is deliberately huge. It flashes in the colour
/// of what the tap earned; a drill that grades its own taps passes
/// `hapticOnTap: false` and plays the graded haptic itself.
struct BigTapTarget: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool
    var flashColor: Color = Theme.Color.speedGreen
    var hapticOnTap = true
    let onTap: () -> Void

    @State private var flash: Bool = false

    var body: some View {
        Button {
            if hapticOnTap {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
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
        return flash ? flashColor : Theme.Color.accent
    }
}

// MARK: - Results

/// Sign is the coaching cue: a consistent bias is a fixable habit, whereas
/// noise around zero just means the count is loose.
private func timingSummary(_ average: Double) -> String {
    let magnitude = Int(abs(average).rounded())
    if magnitude < 25 {
        return "Dead on — average \(magnitude)ms off."
    }
    return average < 0
        ? "Running early by \(magnitude)ms on average."
        : "Running late by \(magnitude)ms on average."
}

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
                CountBadge(label: "Missed", value: score.misses, tint: DrillPalette.error)
                CountBadge(label: "Stray", value: score.falsePositives, tint: DrillPalette.stray)
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
}

/// Results for Tap the Beat.
///
/// Every tap lands within half a beat of *some* beat, so caught-versus-
/// missed says little here. What matters is how tight the taps were, so
/// the headline is the share of beats caught cleanly and the badges are the
/// same timing buckets Practice's step-timing mode uses — one vocabulary
/// for "on the beat" across the app.
struct BeatTapResultsCard: View {
    let score: PhraseScore
    let onRetry: () -> Void

    private var buckets: BucketCounts {
        StepTimingStats.bucketCounts(score.offsetsMs.map { StepTap(time: 0, offsetMs: $0) })
    }

    /// Perfect and good hits over every beat that was there to catch.
    private var onBeatPercent: Int {
        let beats = score.hits + score.misses
        guard beats > 0 else { return 0 }
        return Int((Double(buckets.perfect + buckets.good) / Double(beats) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(onBeatPercent)%")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
                Text("on the beat")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Button("Again", action: onRetry)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }

            HStack(spacing: 8) {
                CountBadge(label: "Perfect", value: buckets.perfect, tint: StepRating.perfect.color)
                CountBadge(label: "Good", value: buckets.good, tint: StepRating.good.color)
                CountBadge(label: "Off", value: buckets.off, tint: StepRating.off.color)
                if score.misses > 0 {
                    CountBadge(label: "Missed", value: score.misses, tint: DrillPalette.error)
                }
                if score.falsePositives > 0 {
                    CountBadge(label: "Extra", value: score.falsePositives, tint: DrillPalette.stray)
                }
            }

            Text(score.averageOffsetMs.map(timingSummary) ?? "No taps landed on a beat.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(14)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
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
                    .foregroundStyle(result.landedOnOne ? Theme.Color.speedGreen : DrillPalette.error)
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
            if run.phase == .running, exercise.isContinuous {
                TapFeedbackLabel(feedback: run.lastFeedback, exercise: exercise, tapCount: run.taps.count)
            }
            tapTarget
            if let planError = run.planError {
                Text(planError)
                    .font(Theme.Font.caption)
                    .foregroundStyle(DrillPalette.error)
            }
            results
        }
    }

    /// The pad flashes in the colour of what the tap just earned. The
    /// parent grades the tap synchronously inside `onTap`, so by the time
    /// the flash renders `run.lastFeedback` is already the new one.
    private var flashColor: Color {
        guard let feedback = run.lastFeedback else { return Theme.Color.speedGreen }
        return feedback.isHit ? feedback.rating.color : DrillPalette.error
    }

    @ViewBuilder
    private var tapTarget: some View {
        if run.phase == .running {
            BigTapTarget(
                title: "Tap",
                subtitle: exercise.tapPrompt,
                isEnabled: true,
                flashColor: flashColor,
                hapticOnTap: false,
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
            if exercise.gradesEveryBeat {
                BeatTapResultsCard(score: score, onRetry: onStart)
            } else {
                DrillResultsCard(score: score, onRetry: onStart)
            }
        }
    }
}
