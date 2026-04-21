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
