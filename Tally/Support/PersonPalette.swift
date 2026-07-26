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
}

extension Person {
    var color: Color { PersonPalette.color(seed: colorSeed) }
}
