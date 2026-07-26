import Foundation

/// Comparing documents by what they say rather than by identity.
///
/// Parsed markdown carries fresh block identifiers and people with no store identifier
/// yet, so `==` is the wrong question to ask when checking whether an import actually
/// changed anything — or whether a round trip preserved the content.
extension DocumentDraft {

    /// Drops the parts markdown cannot represent, so the result is what a round trip is
    /// expected to preserve exactly.
    public func normalizedForMarkdown() -> DocumentDraft {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.blocks = blocks.compactMap { block in
            // Blank paragraphs exist only as editor spacing.
            guard !(block.kind == .paragraph && block.text.isBlank) else { return nil }
            var normalized = block
            normalized.text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if block.kind == .divider { normalized.text = "" }
            if !block.kind.acceptsIndent { normalized.indent = 0 }
            if !block.kind.acceptsAssignees {
                normalized.assignments = []
                normalized.isDoneSolo = false
            }
            if !block.assignments.isEmpty { normalized.isDoneSolo = false }
            return normalized
        }
        return copy
    }

    /// True when two documents describe the same content, ignoring identifiers.
    public func contentEquals(_ other: DocumentDraft) -> Bool {
        let lhs = normalizedForMarkdown()
        let rhs = other.normalizedForMarkdown()
        guard lhs.title == rhs.title, lhs.blocks.count == rhs.blocks.count else { return false }
        return zip(lhs.blocks, rhs.blocks).allSatisfy { $0.contentEquals($1) }
    }
}

extension BlockDraft {
    public func contentEquals(_ other: BlockDraft) -> Bool {
        kind == other.kind
            && text == other.text
            && indent == other.indent
            && isDoneSolo == other.isDoneSolo
            && assignments.count == other.assignments.count
            && zip(assignments, other.assignments).allSatisfy {
                $0.person.matchKey == $1.person.matchKey && $0.isDone == $1.isDone
            }
    }
}
