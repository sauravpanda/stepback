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
