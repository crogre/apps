import Foundation

/// Reusing a document as the starting point for a new one.
///
/// This is the packing-list workflow: last trip's list becomes this trip's list, with the
/// same items and the same kids assigned, but every box cleared.
public enum TemplateCloner {

    public struct Options: Sendable {
        /// Title of the new document.
        public var title: String
        /// Carry the assignees over. When false the new document keeps the items but
        /// nobody is assigned to them.
        public var keepAssignees: Bool
        /// Swap one person for another, keyed by `PersonRef.matchKey`. Lets last summer's
        /// list be pointed at a different set of people without retyping it.
        public var personRemap: [String: PersonRef]

        public init(
            title: String,
            keepAssignees: Bool = true,
            personRemap: [String: PersonRef] = [:]
        ) {
            self.title = title
            self.keepAssignees = keepAssignees
            self.personRemap = personRemap
        }
    }

    /// A fresh document with the same structure and no progress recorded against it.
    public static func clone(_ source: DocumentDraft, options: Options) -> DocumentDraft {
        let blocks = source.blocks.map { block -> BlockDraft in
            BlockDraft(
                id: UUID(),
                kind: block.kind,
                text: block.text,
                indent: block.indent,
                isDoneSolo: false,
                assignments: options.keepAssignees ? remapped(block.assignments, using: options.personRemap) : []
            )
        }
        return DocumentDraft(id: UUID(), title: options.title, blocks: blocks)
    }

    /// Clears every box in place, keeping identities so the caller can apply the result to
    /// existing stored objects rather than replacing them.
    public static func reset(_ document: DocumentDraft) -> DocumentDraft {
        var result = document
        result.blocks = document.blocks.map { block in
            var copy = block
            copy.isDoneSolo = false
            copy.assignments = block.assignments.map { AssignmentDraft(person: $0.person, isDone: false) }
            return copy
        }
        return result
    }

    /// A default title for a document derived from `source`, e.g. "Packing list — 3 Aug".
    public static func suggestedTitle(
        basedOn source: DocumentDraft,
        date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let base = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        let stamp = formatter.string(from: date)
        return base.isEmpty ? stamp : "\(base) — \(stamp)"
    }

    private static func remapped(
        _ assignments: [AssignmentDraft],
        using remap: [String: PersonRef]
    ) -> [AssignmentDraft] {
        var seen = Set<String>()
        var result: [AssignmentDraft] = []
        for assignment in assignments {
            let person = remap[assignment.person.matchKey] ?? assignment.person
            // Two different people can be remapped onto the same person; collapse them so
            // an item does not end up assigned to somebody twice.
            guard seen.insert(person.matchKey).inserted else { continue }
            result.append(AssignmentDraft(person: person, isDone: false))
        }
        return result
    }
}
