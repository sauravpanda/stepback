import SwiftUI

// MARK: - BPM badge + detect button

struct BPMBadge: View {
    let bpm: Double?
    let isAnalyzing: Bool
    let measurePosition: Int?
    let beatsPerMeasure: Int
    let onDetect: () -> Void
    var onRescale: ((Double) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let bpm {
                Text("\(Int(bpm.rounded())) BPM")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                if let onRescale {
                    RescaleButton(label: "÷2") { onRescale(0.5) }
                    RescaleButton(label: "×2") { onRescale(2) }
                }
                if let measurePosition {
                    MeasureCounter(current: measurePosition, total: beatsPerMeasure)
                }
            } else if isAnalyzing {
                ProgressView()
                    .tint(Theme.Color.accent)
                Text("Detecting beats…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                Button(action: onDetect) {
                    Label("Detect beats", systemImage: "waveform")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Color.accentSoft, in: Capsule())
    }
}

// MARK: - Rescale button

private struct RescaleButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 24, height: 20)
                .background(Theme.Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Count-in-measure indicator

struct MeasureCounter: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { slot in
                let isCurrent = slot == current
                Text("\(slot)")
                    .font(.system(.caption2, design: .rounded, weight: isCurrent ? .black : .regular))
                    .foregroundStyle(isCurrent ? Theme.Color.accent : Theme.Color.textTertiary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(isCurrent ? Theme.Color.accent.opacity(0.25) : .clear)
                    )
            }
        }
    }
}

// MARK: - Step timing panel

struct StepTimingPanel: View {
    let taps: [StepTap]
    let isActive: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Step timing", systemImage: "metronome")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(isActive ? Theme.Color.accent : Theme.Color.textSecondary)
                Spacer()
                Button(isActive ? "Stop" : "Start", action: onToggle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.accent)
            }
            if isActive {
                tapButton
                StepHistogram(taps: taps)
                    .frame(height: 44)
                summary
            }
        }
        .padding(12)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var tapButton: some View {
        Button(action: onTap) {
            Text("Tap")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.Color.accent, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        let average = StepTimingStats.averageOffsetMs(taps)
        let counts = StepTimingStats.bucketCounts(taps)
        return HStack(spacing: 14) {
            if let average {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avg offset")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(averageText(average))
                        .font(Theme.Font.timestamp)
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            } else {
                Text("Tap along with the beat")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            if !taps.isEmpty {
                BucketBadge(color: StepRating.perfect.color, count: counts.perfect)
                BucketBadge(color: StepRating.good.color, count: counts.good)
                BucketBadge(color: StepRating.off.color, count: counts.off)
                Button("Reset", action: onReset)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    private func averageText(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        let descriptor = value > 0 ? "late" : value < 0 ? "early" : "on beat"
        return "\(sign)\(Int(value.rounded())) ms (\(descriptor))"
    }
}

private struct StepHistogram: View {
    let taps: [StepTap]

    var body: some View {
        GeometryReader { geo in
            if taps.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Color.surfaceElevated)
            } else {
                let count = taps.count
                let spacing: CGFloat = 2
                let availableWidth = max(0, geo.size.width - CGFloat(count - 1) * spacing)
                let barWidth = max(1, availableWidth / CGFloat(count))
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(taps) { tap in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(StepRating(offsetMs: tap.offsetMs).color)
                            .frame(width: barWidth, height: barHeight(for: tap.offsetMs, in: geo.size.height))
                            .offset(y: tap.offsetMs > 0 ? (geo.size.height - barHeight(for: tap.offsetMs, in: geo.size.height)) / 2 : -(geo.size.height - barHeight(for: tap.offsetMs, in: geo.size.height)) / 2)
                    }
                }
            }
        }
    }

    private func barHeight(for offsetMs: Double, in total: CGFloat) -> CGFloat {
        let magnitude = min(200.0, abs(offsetMs))
        let ratio = magnitude / 200.0
        return max(6, total * CGFloat(ratio))
    }
}

private struct BucketBadge: View {
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)")
                .font(Theme.Font.timestamp)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

// MARK: - Downbeat anchor controls

struct DownbeatAnchorBar: View {
    let hasAnchor: Bool
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if hasAnchor {
                Label("Beat 1 locked", systemImage: "checkmark.circle.fill")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Spacer()
                Button("Reset", action: onClear)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                Button(action: onTap) {
                    Label("Tap on beat 1", systemImage: "hand.tap")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }
}
