import Foundation
import SwiftData

/// Somebody a todo can be assigned to.
///
/// People are local to the device and exist independently of any one document, which is
/// what makes "choose from earlier entries" possible when assigning.
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    /// Index into `PersonPalette`, so a person keeps the same colour everywhere.
    var colorSeed: Int = 0
    /// A colour picked outside the palette, as `#RRGGBB`. Wins over `colorSeed` when set.
    var customColorHex: String? = nil
    var createdAt: Date = Date.now
    /// Bumped whenever the person is assigned to something. Orders the picker so the
    /// people you actually use float to the top.
    var lastUsedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Assignment.person)
    var assignments: [Assignment]? = []

    init(name: String, colorSeed: Int? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.colorSeed = colorSeed ?? PersonPalette.seed(for: name)
        self.createdAt = createdAt
        self.lastUsedAt = createdAt
    }

    /// SwiftData exposes to-many relationships as optionals for CloudKit compatibility;
    /// callers should never have to think about that.
    var allAssignments: [Assignment] { assignments ?? [] }

    /// How many todos this person is currently on the hook for.
    var openAssignmentCount: Int {
        allAssignments.filter { !$0.isDone }.count
    }

    var initials: String {
        let words = name
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    func markUsed(at date: Date = .now) {
        lastUsedAt = date
    }
}
