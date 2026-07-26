import Foundation
import SwiftData

/// Structural edits to a document's blocks.
///
/// Kept apart from the views so the editor's SwiftUI code only has to worry about text and
/// focus, and so the ordering arithmetic lives in one place.
struct EditorCommands {
    let document: Document
    let context: ModelContext

    // MARK: - Inserting

    /// Inserts a new block directly after `block` (or at the top when it is nil).
    @discardableResult
    func insert(
        kind: BlockKind = .paragraph,
        text: String = "",
        indent: Int = 0,
        after block: Block?
    ) -> Block {
        let ordered = document.orderedBlocks
        let index = block.flatMap { candidate in ordered.firstIndex { $0.id == candidate.id } }

        let before = index.map { ordered[$0].position }
        let after: Double? = {
            guard let index, index + 1 < ordered.count else { return nil }
            return ordered[index + 1].position
        }()

        let new = Block(
            kind: kind,
            text: text,
            position: FractionalIndex.between(before, after),
            indent: indent
        )
        context.insert(new)
        new.document = document
        document.touch()
        renormalizeIfNeeded()
        return new
    }

    /// Appends a block at the very end.
    @discardableResult
    func append(kind: BlockKind = .paragraph, text: String = "", indent: Int = 0) -> Block {
        insert(kind: kind, text: text, indent: indent, after: document.orderedBlocks.last)
    }

    // MARK: - Splitting and merging

    /// Return pressed mid-line: everything from `offset` moves into a new block below.
    ///
    /// Assignees stay with the original item — the new line is a new task, and the editor
    /// decides separately whether to carry the current assignees over.
    @discardableResult
    func split(_ block: Block, at offset: Int) -> Block {
        let characters = Array(block.text)
        let safeOffset = max(0, min(offset, characters.count))
        let head = String(characters[..<safeOffset])
        let tail = String(characters[safeOffset...])

        block.text = head

        // Headings do not continue; the line after a heading is ordinary prose.
        let newKind: BlockKind = block.kind.continuesOnReturn ? block.kind : .paragraph
        return insert(kind: newKind, text: tail, indent: block.indent, after: block)
    }

    /// Return on an empty list item: drop back out to a plain paragraph rather than
    /// creating another empty bullet, the way Notes and every markdown editor behave.
    /// Returns true when it handled the keystroke.
    func outdentOrPlain(_ block: Block) -> Bool {
        guard block.kind.continuesOnReturn, block.text.isEmpty else { return false }
        if block.indent > 0 {
            block.indent -= 1
        } else {
            block.kind = .paragraph
            clearAssignments(on: block)
        }
        document.touch()
        return true
    }

    /// Backspace at the start of a line: fold this block into the one above.
    ///
    /// Returns the block that now has focus and where the caret should sit inside it.
    func mergeBackward(_ block: Block) -> (target: Block, caretOffset: Int)? {
        let ordered = document.orderedBlocks
        guard let index = ordered.firstIndex(where: { $0.id == block.id }), index > 0 else { return nil }
        let previous = ordered[index - 1]

        // Backspacing into a divider removes the divider instead of merging text into it.
        if previous.kind == .divider {
            delete(previous)
            return (block, 0)
        }

        // A decorated line first loses its decoration; a second backspace then merges.
        if block.kind != .paragraph {
            block.kind = .paragraph
            block.indent = 0
            clearAssignments(on: block)
            document.touch()
            return (block, 0)
        }

        let caret = previous.text.count
        previous.text += block.text
        delete(block)
        return (previous, caret)
    }

    // MARK: - Changing blocks

    func setKind(_ kind: BlockKind, on block: Block) {
        guard block.kind != kind else { return }
        block.kind = kind
        if !kind.acceptsIndent { block.indent = 0 }
        if !kind.acceptsAssignees { clearAssignments(on: block) }
        if kind == .divider { block.text = "" }
        document.touch()
    }

    func adjustIndent(_ block: Block, by delta: Int) {
        guard block.kind.acceptsIndent else { return }
        block.indent = max(0, min(block.indent + delta, MarkdownSyntax.maxIndent))
        document.touch()
    }

    func delete(_ block: Block) {
        context.delete(block)
        document.touch()
    }

    /// Drag-to-reorder from the list.
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var ordered = document.orderedBlocks
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, block) in ordered.enumerated() {
            block.position = Double(index) * FractionalIndex.step
        }
        document.touch()
    }

    // MARK: - Assignees

    /// Replaces a todo's assignees, preserving the completion already recorded for people
    /// who stay on the item.
    func setAssignees(_ people: [Person], on block: Block, date: Date = .now) {
        guard block.kind == .todo else { return }

        let existing = block.orderedAssignments
        var keptByPersonID: [UUID: Assignment] = [:]
        for assignment in existing {
            if let id = assignment.person?.id, people.contains(where: { $0.id == id }) {
                keptByPersonID[id] = assignment
            } else {
                context.delete(assignment)
            }
        }

        for (index, person) in people.enumerated() {
            person.markUsed(at: date)
            if let kept = keptByPersonID[person.id] {
                kept.order = index
            } else {
                let assignment = Assignment(person: person, order: index)
                context.insert(assignment)
                assignment.block = block
            }
        }

        // The unassigned fallback flag would otherwise linger and confuse the rollup.
        if !people.isEmpty { block.isDoneSolo = false }
        document.touch()
    }

    private func clearAssignments(on block: Block) {
        for assignment in block.orderedAssignments {
            context.delete(assignment)
        }
        block.isDoneSolo = false
    }

    // MARK: - Housekeeping

    /// Repeated splitting in the same spot eventually exhausts the gap between two
    /// positions; when that happens the whole document gets evenly renumbered.
    private func renormalizeIfNeeded() {
        let ordered = document.orderedBlocks
        guard FractionalIndex.needsRenormalisation(ordered.map(\.position)) else { return }
        for (index, block) in ordered.enumerated() {
            block.position = Double(index) * FractionalIndex.step
        }
    }
}
