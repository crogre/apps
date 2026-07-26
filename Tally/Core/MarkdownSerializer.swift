import Foundation

/// Renders a document as markdown for sharing and export.
///
/// See `MarkdownSyntax` for the format. `MarkdownParser` reads back everything written
/// here; the one deliberate asymmetry is that empty paragraph blocks (used purely as
/// spacing in the editor) are not represented, because a blank line in markdown already
/// means "separator" and encoding the difference would make the output unpleasant to read.
public enum MarkdownSerializer {

    public struct Options: Sendable {
        /// Emit the document title as a leading level-1 heading.
        public var includeTitleHeading: Bool
        /// Emit blank lines between blocks so the result renders correctly in a normal
        /// markdown viewer. Turning this off produces the most compact form.
        public var prettySpacing: Bool

        public init(includeTitleHeading: Bool = true, prettySpacing: Bool = true) {
            self.includeTitleHeading = includeTitleHeading
            self.prettySpacing = prettySpacing
        }

        public static let `default` = Options()
    }

    public static func markdown(for document: DocumentDraft, options: Options = .default) -> String {
        var lines: [String] = []

        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if options.includeTitleHeading && !title.isEmpty {
            lines.append("# \(title)")
        }

        var previous: BlockDraft?
        for block in document.blocks {
            // Spacing blocks carry no content of their own.
            if block.kind == .paragraph && block.text.isBlank { continue }

            if options.prettySpacing, needsBlankLineBetween(previous, block) || (previous == nil && !lines.isEmpty) {
                lines.append("")
            }
            lines.append(line(for: block))
            previous = block
        }

        return lines.joined(separator: "\n")
    }

    /// Markdown for a single block, without any surrounding blank lines.
    public static func line(for block: BlockDraft) -> String {
        let indent = String(
            repeating: MarkdownSyntax.indentUnit,
            count: max(0, min(block.indent, MarkdownSyntax.maxIndent))
        )
        let text = block.text.trimmingTrailingWhitespace()

        switch block.kind {
        case .divider:
            return "---"
        case .heading1:
            return "# \(text)"
        case .heading2:
            return "## \(text)"
        case .heading3:
            return "### \(text)"
        case .paragraph:
            return text
        case .bullet:
            return "\(indent)- \(text)"
        case .todo:
            let box = block.completion.isComplete ? "[x]" : "[ ]"
            let mentions = block.assignments
                .map { MarkdownSyntax.mention(for: $0.person, isDone: $0.isDone) }
                .joined(separator: " ")
            let body = mentions.isEmpty ? text : "\(text) \(mentions)"
            return "\(indent)- \(box) \(body)"
        }
    }

    /// Markdown viewers merge adjacent lines into one paragraph and need a blank line to
    /// start a new block, but list items must stay packed together or the list breaks
    /// into separate lists.
    private static func needsBlankLineBetween(_ previous: BlockDraft?, _ next: BlockDraft) -> Bool {
        guard let previous else { return false }
        let bothAreListItems = previous.kind.continuesOnReturn && next.kind.continuesOnReturn
        return !bothAreListItems
    }
}
