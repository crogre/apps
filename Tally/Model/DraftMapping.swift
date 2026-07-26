import Foundation
import SwiftData

/// Bridges the stored SwiftData objects and the plain value types in `Core`.
///
/// Everything that needs real logic — markdown, template cloning, completion arithmetic —
/// works on drafts, which is why that logic can be unit-tested without a store. This file
/// is the only place that knows about both worlds.

extension Block {
    var draft: BlockDraft {
        BlockDraft(
            id: id,
            kind: kind,
            text: text,
            indent: indent,
            isDoneSolo: isDoneSolo,
            assignments: orderedAssignments.map { assignment in
                AssignmentDraft(
                    person: PersonRef(id: assignment.person?.id, name: assignment.personName),
                    isDone: assignment.isDone
                )
            }
        )
    }
}

extension Document {
    var draft: DocumentDraft {
        DocumentDraft(id: id, title: title, blocks: orderedBlocks.map(\.draft))
    }

    var markdown: String {
        MarkdownSerializer.markdown(for: draft)
    }
}

enum DocumentMaterializer {

    /// Creates and inserts a document built from a draft, resolving every named person
    /// against the store so imports and clones reuse the people you already have.
    @discardableResult
    static func makeDocument(
        from draft: DocumentDraft,
        in context: ModelContext,
        isTemplate: Bool = false,
        templateSourceID: UUID? = nil,
        date: Date = .now
    ) -> Document {
        let document = Document(title: draft.title, isTemplate: isTemplate, createdAt: date)
        document.templateSourceID = templateSourceID
        context.insert(document)
        append(draft.blocks, to: document, in: context, date: date)
        return document
    }

    /// Appends blocks to the end of a document.
    static func append(
        _ blocks: [BlockDraft],
        to document: Document,
        in context: ModelContext,
        date: Date = .now
    ) {
        let people = PersonStore(context: context)
        var position = FractionalIndex.append(after: document.orderedBlocks.map(\.position))

        for blockDraft in blocks {
            let block = Block(
                kind: blockDraft.kind,
                text: blockDraft.text,
                position: position,
                indent: blockDraft.indent,
                isDoneSolo: blockDraft.isDoneSolo
            )
            context.insert(block)
            block.document = document

            for (index, assignmentDraft) in blockDraft.assignments.enumerated() {
                guard let person = people.resolve(assignmentDraft.person) else { continue }
                person.markUsed(at: date)
                let assignment = Assignment(
                    person: person,
                    order: index,
                    completedAt: assignmentDraft.isDone ? date : nil
                )
                context.insert(assignment)
                assignment.block = block
            }

            position += FractionalIndex.step
        }

        document.touch(date)
    }

    /// Clears every box in a document in place, keeping the blocks and their assignees.
    /// This is "reuse the list I already have" rather than "start a new one".
    static func resetCompletion(in document: Document, date: Date = .now) {
        for block in document.orderedBlocks {
            block.isDoneSolo = false
            for assignment in block.orderedAssignments {
                assignment.completedAt = nil
            }
        }
        document.touch(date)
    }
}
