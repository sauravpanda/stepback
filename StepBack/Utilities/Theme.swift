import SwiftUI

enum Theme {

    enum Color {
        static let background = SwiftUI.Color(hex: 0x0A0A0F)
        static let surface = SwiftUI.Color(hex: 0x171720)
        static let surfaceElevated = SwiftUI.Color(hex: 0x22222C)

        static let accent = SwiftUI.Color(hex: 0xFF3B7F)
        static let accentSoft = accent.opacity(0.15)

        static let textPrimary = SwiftUI.Color.white
        static let textSecondary = SwiftUI.Color.white.opacity(0.72)
        static let textTertiary = SwiftUI.Color.white.opacity(0.48)

        static let divider = SwiftUI.Color.white.opacity(0.08)

        static let speedCyan = SwiftUI.Color(hex: 0x5FE7FF)
        static let speedGreen = SwiftUI.Color(hex: 0x5FFFA8)
        static let speedWhite = SwiftUI.Color.white
        static let speedOrange = SwiftUI.Color(hex: 0xFFA13B)

        static func speedPillColor(for speed: Double) -> SwiftUI.Color {
            switch speed {
            case ..<0.5: speedCyan
            case ..<1.0: speedGreen
            case 1.0: speedWhite
            default: speedOrange
            }
        }
    }

    enum Font {
        static let display = SwiftUI.Font.system(.largeTitle, design: .rounded, weight: .black)
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .bold)
        static let body = SwiftUI.Font.system(.body, design: .default, weight: .regular)
        static let bodyEmphasized = SwiftUI.Font.system(.body, design: .default, weight: .semibold)
        static let caption = SwiftUI.Font.system(.caption, design: .default, weight: .regular)
        static let timestamp = SwiftUI.Font.system(.footnote, design: .monospaced, weight: .medium)
    }

    enum Metrics {
        static let cornerRadius: CGFloat = 14
        static let pillRadius: CGFloat = 999
        static let spacing: CGFloat = 12
        static let tightSpacing: CGFloat = 6
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Parses a `"#RRGGBB"` or `"RRGGBB"` string into a Color. Falls back to
    /// the theme accent if the string isn't a valid hex triplet.
    init(tagHex: String) {
        let stripped: Substring = tagHex.hasPrefix("#") ? tagHex.dropFirst() : Substring(tagHex)
        let value = UInt32(stripped, radix: 16) ?? 0xFF3B7F
        self.init(hex: value)
    }
}
