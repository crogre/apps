import Foundation
import SwiftData

/// Look-up and creation of people.
///
/// Names are matched case-insensitively so importing `@alma` twice, or once as `@Alma`,
/// does not leave you with two Almas. There is deliberately no unique constraint on the
/// model itself — SwiftData's CloudKit support forbids them, and we want that door open.
struct PersonStore {
    let context: ModelContext

    func allPeople() -> [Person] {
        let descriptor = FetchDescriptor<Person>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// People ordered for the assignee picker: most recently used first.
    func suggestions(matching query: String = "") -> [Person] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allPeople() }
        return allPeople().filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    func person(named name: String) -> Person? {
        let key = PersonRef(name: name).matchKey
        guard !key.isEmpty else { return nil }
        return allPeople().first { PersonRef(name: $0.name).matchKey == key }
    }

    /// Finds a person by name or creates them. Returns `nil` for a blank name.
    @discardableResult
    func findOrCreate(named name: String) -> Person? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = person(named: trimmed) { return existing }
        let person = Person(name: trimmed)
        context.insert(person)
        return person
    }

    /// Resolves a reference that came from parsed markdown or a template clone.
    func resolve(_ ref: PersonRef) -> Person? {
        if let id = ref.id, let match = allPeople().first(where: { $0.id == id }) {
            return match
        }
        return findOrCreate(named: ref.name)
    }

    /// Removes a person and, by cascade, every assignment naming them. Items they were the
    /// only assignee of stay in place and become unassigned.
    func delete(_ person: Person) {
        context.delete(person)
    }

    /// How many todos would be affected by deleting this person — shown in the warning.
    func impactOfDeleting(_ person: Person) -> Int {
        person.allAssignments.count
    }
}
