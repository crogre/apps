import Foundation

/// Value-type mirrors of the persisted model.
///
/// Everything interesting — markdown, template cloning, completion arithmetic — is
/// expressed against these instead of against SwiftData objects, so it can be unit-tested
/// without a store and without a simulator. The app converts in both directions in
/// `DraftMapping.swift`.

/// A person referenced from a draft. `id` is `nil` for people that came from parsed
/// markdown and have not yet been matched against the store.
public struct PersonRef: Codable, Hashable, Sendable {
    public var id: UUID?
    public var name: String

    public init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }

    /// Names are matched case- and whitespace-insensitively when importing.
    public var matchKey: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct AssignmentDraft: Codable, Hashable, Sendable {
    public var person: PersonRef
    public var isDone: Bool

    public init(person: PersonRef, isDone: Bool = false) {
        self.person = person
        self.isDone = isDone
    }
}

public struct BlockDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: BlockKind
    public var text: String
    public var indent: Int
    /// Completion for a todo that has nobody assigned to it.
    public var isDoneSolo: Bool
    public var assignments: [AssignmentDraft]

    public init(
        id: UUID = UUID(),
        kind: BlockKind = .paragraph,
        text: String = "",
        indent: Int = 0,
        isDoneSolo: Bool = false,
        assignments: [AssignmentDraft] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.indent = indent
        self.isDoneSolo = isDoneSolo
        self.assignments = assignments
    }

    public var completion: CompletionRollup {
        CompletionRollup(
            doneCount: assignments.filter(\.isDone).count,
            totalCount: assignments.count,
            isDoneSolo: isDoneSolo
        )
    }

    public var people: [PersonRef] { assignments.map(\.person) }
}

public struct DocumentDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var blocks: [BlockDraft]

    public init(id: UUID = UUID(), title: String = "", blocks: [BlockDraft] = []) {
        self.id = id
        self.title = title
        self.blocks = blocks
    }

    /// Every distinct person mentioned anywhere in the document, in first-appearance order.
    /// Drives the remap list in the "new from this document" sheet.
    public var distinctPeople: [PersonRef] {
        var seen = Set<String>()
        var result: [PersonRef] = []
        for block in blocks {
            for person in block.people where seen.insert(person.matchKey).inserted {
                result.append(person)
            }
        }
        return result
    }

    public var todoCount: Int {
        blocks.filter { $0.kind == .todo }.count
    }

    public var completedTodoCount: Int {
        blocks.filter { $0.kind == .todo && $0.completion.isComplete }.count
    }
}
