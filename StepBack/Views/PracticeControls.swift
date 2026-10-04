import SwiftUI

// MARK: - Speed pills

struct SpeedPills: View {
    static let speeds: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5]
    let selected: Double
    let onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.speeds, id: \.self) { speed in
                let isSelected = SpeedFormatter.equals(selected, speed)
                let tint = Theme.Color.speedPillColor(for: speed)
                Button {
                    onSelect(speed)
                } label: {
                    Text(SpeedFormatter.pill(speed))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? tint : Theme.Color.surfaceElevated)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Speed menu (compact form for the practice transport row)

/// Compact speed control for places where a full pill row is too wide.
/// Shows the current speed as a tinted capsule with a chevron; tapping
/// opens a Menu with the same set of speeds as `SpeedPills`. Used in the
/// merged transport row on PracticeView so play / A-B / speed all live on
/// one line. Keeps `SpeedPills` for the segment sheets, where vertical
/// space isn't tight and the always-visible options are easier to scan.
struct SpeedMenuButton: View {
    let selected: Double
    let onSelect: (Double) -> Void

    var body: some View {
        let tint = Theme.Color.speedPillColor(for: selected)
        Menu {
            Picker("Practice speed", selection: bindingSpeed) {
                ForEach(SpeedPills.speeds, id: \.self) { speed in
                    Text(SpeedFormatter.pill(speed)).tag(speed)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(SpeedFormatter.pill(selected))
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(.black)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Practice speed: \(SpeedFormatter.pill(selected))")
    }

    /// Bridges the let-based API (selected + onSelect) into the Binding the
    /// Picker needs without forcing the parent to hand us one.
    private var bindingSpeed: Binding<Double> {
        Binding(get: { selected }, set: onSelect)
    }
}

// MARK: - Formatting

enum SpeedFormatter {
    static func pill(_ speed: Double) -> String {
        let base: String
        if speed == speed.rounded() {
            base = "\(Int(speed))"
        } else {
            base = String(format: "%g", speed)
        }
        return "\(base)×"
    }

    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let totalCentis = Int((seconds * 100).rounded())
        let mins = totalCentis / 6000
        let secs = (totalCentis / 100) % 60
        let cent = totalCentis % 100
        return String(format: "%d:%02d.%02d", mins, secs, cent)
    }

    static func equals(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.001
    }
}

// MARK: - Action pill

/// Labeled pill button for the practice action row. Two visual variants:
/// `.accent` (filled accent) for the primary action when ready, `.surface`
/// for a neutral secondary action, `.surfaceMuted` for a disabled state.
struct ActionPill: View {
    enum Tint { case accent, surface, surfaceMuted }

    let title: String
    let systemImage: String
    let tint: Tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tint {
        case .accent: .black
        case .surface: Theme.Color.textPrimary
        case .surfaceMuted: Theme.Color.textTertiary
        }
    }

    private var background: Color {
        switch tint {
        case .accent: Theme.Color.accent
        case .surface: Theme.Color.surfaceElevated
        case .surfaceMuted: Theme.Color.surface
        }
    }
}

// MARK: - Frame step

struct FrameStepButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loop controls

struct LoopButton: View {
    let label: String
    let filled: Bool
    let caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(filled ? .black : Theme.Color.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(filled ? Theme.Color.accent : Theme.Color.surfaceElevated)
                    )
                if let caption {
                    Text(caption)
                        .font(Theme.Font.timestamp)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
