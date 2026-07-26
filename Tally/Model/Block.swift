import Foundation
import SwiftData

/// One line of a document: a heading, a paragraph, a bullet, a todo, or a divider.
@Model
final class Block {
    var id: UUID = UUID()
    /// Fractional index — see `FractionalIndex`. Inserting between two lines is a single
    /// write rather than a renumbering of everything below.
    var position: Double = 0
    /// Persisted form of `BlockKind`. Raw strings rather than an enum so that an unknown
    /// future value read back from disk degrades to a paragraph instead of failing to load.
    var kindRaw: String = BlockKind.paragraph.rawValue
    /// Inline markdown source: `**bold**`, `_italic_`, `` `code` ``.
    var text: String = ""
    var indent: Int = 0
    /// Completion for a todo with nobody assigned. Ignored once there are assignees.
    var isDoneSolo: Bool = false

    var document: Document?

    @Relationship(deleteRule: .cascade, inverse: \Assignment.block)
    var assignments: [Assignment]? = []

    init(
        kind: BlockKind = .paragraph,
        text: String = "",
        position: Double = 0,
        indent: Int = 0,
        isDoneSolo: Bool = false
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.text = text
        self.position = position
        self.indent = indent
        self.isDoneSolo = isDoneSolo
    }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .paragraph }
        set { kindRaw = newValue.rawValue }
    }

    /// Assignments in their stored order.
    var orderedAssignments: [Assignment] {
        (assignments ?? []).sorted { $0.order < $1.order }
    }

    var people: [Person] {
        orderedAssignments.compactMap(\.person)
    }

    var completion: CompletionRollup {
        let all = assignments ?? []
        return CompletionRollup(
            doneCount: all.filter(\.isDone).count,
            totalCount: all.count,
            isDoneSolo: isDoneSolo
        )
    }

    /// Ticking is only ambiguous when more than one person is on the item.
    var needsCompleterPrompt: Bool { completion.needsCompleterPrompt }

    // MARK: - Mutation

    /// Ticks or unticks the whole item, for the unambiguous cases.
    func setCompleted(_ completed: Bool, at date: Date = .now) {
        let all = orderedAssignments
        if all.isEmpty {
            isDoneSolo = completed
        } else {
            for assignment in all {
                assignment.completedAt = completed ? (assignment.completedAt ?? date) : nil
            }
        }
    }

    /// Flips the whole item, used by the single-assignee tap path.
    func toggleCompleted(at date: Date = .now) {
        setCompleted(!completion.isComplete, at: date)
    }

    func assignment(for person: Person) -> Assignment? {
        orderedAssignments.first { $0.person?.id == person.id }
    }
}
