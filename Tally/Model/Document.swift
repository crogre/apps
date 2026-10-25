import Foundation
import SwiftData

/// A note. A title plus an ordered list of blocks.
@Model
final class Document {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Pins the document into the Templates section of the list — the packing list you
    /// reach for every trip.
    var isTemplate: Bool = false
    /// The document this one was cloned from, kept as a plain identifier rather than a
    /// relationship so deleting the original never disturbs its descendants.
    var templateSourceID: UUID?
    /// This note's own order of people, as comma-separated person ids. Nil follows the
    /// global order. Stored as a string to stay a plain attribute for CloudKit.
    var peopleOrderRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \Block.document)
    var blocks: [Block]? = []

    init(title: String = "", isTemplate: Bool = false, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.isTemplate = isTemplate
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var orderedBlocks: [Block] {
        (blocks ?? []).sorted { $0.position < $1.position }
    }

    var todoBlocks: [Block] {
        orderedBlocks.filter { $0.kind == .todo }
    }

    var completedTodoCount: Int {
        todoBlocks.filter { $0.completion.isComplete }.count
    }

    /// "3 of 8" for the document list. Nil when the document has no todos at all.
    var progressSummary: String? {
        let todos = todoBlocks
        guard !todos.isEmpty else { return nil }
        return "\(todos.filter { $0.completion.isComplete }.count) of \(todos.count)"
    }

    /// First non-empty line after the title, shown as the list subtitle.
    var preview: String {
        for block in orderedBlocks where !block.text.isBlank {
            return block.text
        }
        return ""
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Everyone mentioned anywhere in this document, in this note's people order. Drives
    /// the avatar stack and the remap list when using the document as a template.
    var distinctPeople: [Person] {
        var seen = Set<UUID>()
        var result: [Person] = []
        for block in orderedBlocks {
            for person in block.people where seen.insert(person.id).inserted {
                result.append(person)
            }
        }
        return PeopleOrder.sorted(result, in: self)
    }

    /// This note's own order of people, or nil when it follows the global order.
    var peopleOrderOverride: [UUID]? {
        get {
            guard let peopleOrderRaw else { return nil }
            return peopleOrderRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
        set {
            peopleOrderRaw = newValue?.map(\.uuidString).joined(separator: ",")
        }
    }

    func touch(_ date: Date = .now) {
        updatedAt = date
    }
}
