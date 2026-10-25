import Foundation

/// The one place that decides what order people appear in.
///
/// A note can carry its own order; anyone it does not mention, or every person in a note
/// without one, follows the global order from the People screen. Ties in the global order
/// fall back to who was created first, so a fresh install still has a stable order.
enum PeopleOrder {

    static func sorted(_ people: [Person], in document: Document?) -> [Person] {
        let noteRanks = ranks(for: document)
        return people.sorted { isOrderedBefore($0, $1, noteRanks: noteRanks) }
    }

    static func sorted(_ assignments: [Assignment], in document: Document?) -> [Assignment] {
        let noteRanks = ranks(for: document)
        return assignments.sorted { lhs, rhs in
            switch (lhs.person, rhs.person) {
            case let (left?, right?) where left.id != right.id:
                return isOrderedBefore(left, right, noteRanks: noteRanks)
            default:
                return lhs.order < rhs.order
            }
        }
    }

    /// Everyone, in the global order — what the People screen shows and edits.
    static func global(_ people: [Person]) -> [Person] {
        sorted(people, in: nil)
    }

    /// Writes `people` back as the global order, numbering from 0.
    static func setGlobal(_ people: [Person]) {
        for (index, person) in people.enumerated() where person.sortIndex != index {
            person.sortIndex = index
        }
    }

    /// The next free spot at the end of the global order, for someone new.
    static func nextGlobalIndex(after people: [Person]) -> Int {
        (people.map(\.sortIndex).max() ?? -1) + 1
    }

    private static func ranks(for document: Document?) -> [UUID: Int] {
        guard let order = document?.peopleOrderOverride else { return [:] }
        return Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func isOrderedBefore(_ lhs: Person, _ rhs: Person, noteRanks: [UUID: Int]) -> Bool {
        let left = noteRanks[lhs.id] ?? Int.max
        let right = noteRanks[rhs.id] ?? Int.max
        if left != right { return left < right }
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
