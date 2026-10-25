import SwiftUI

/// Stable colours for people, so Alma is the same green on every item and you can read a
/// chip row at a glance without reading the names.
enum PersonPalette {
    static let colors: [Color] = [
        Color(red: 0.20, green: 0.55, blue: 0.90),  // blue
        Color(red: 0.90, green: 0.40, blue: 0.35),  // coral
        Color(red: 0.30, green: 0.68, blue: 0.42),  // green
        Color(red: 0.80, green: 0.55, blue: 0.15),  // amber
        Color(red: 0.58, green: 0.40, blue: 0.85),  // violet
        Color(red: 0.15, green: 0.65, blue: 0.68),  // teal
        Color(red: 0.86, green: 0.42, blue: 0.62),  // pink
        Color(red: 0.45, green: 0.50, blue: 0.58),  // slate
    ]

    /// Derived from the name so a person gets a sensible colour without being asked, and
    /// the same name always lands on the same one.
    static func seed(for name: String) -> Int {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return 0 }
        // A small stable hash — `hashValue` is seeded per process and would give a person
        // a different colour on every launch.
        var total = 0
        for scalar in normalized.unicodeScalars {
            total = (total &* 31 &+ Int(scalar.value)) % 1_000_003
        }
        return abs(total) % colors.count
    }

    static func color(seed: Int) -> Color {
        colors[((seed % colors.count) + colors.count) % colors.count]
    }

    /// `#RRGGBB` for a colour, so a custom pick can be stored as a plain string.
    static func hex(for color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let channel = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }

    static func color(hex: String) -> Color? {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Person {
    var color: Color {
        if let customColorHex, let custom = PersonPalette.color(hex: customColorHex) {
            return custom
        }
        return PersonPalette.color(seed: colorSeed)
    }
}
