import Foundation

/// Reads the markdown written by `MarkdownSerializer`, plus ordinary markdown written by
/// anyone else, back into a document.
///
/// Two rules worth knowing:
///
/// * The first level-1 heading becomes the document title rather than a block, which is
///   what makes `# Trip to Åre` round trip as a title.
/// * `@mentions` are only recognised at the *end* of a todo line, so `email teacher@school`
///   stays part of the text while `- [ ] Socks @Alma` does not.
public enum MarkdownParser {

    public static func document(from markdown: String, fallbackTitle: String = "") -> DocumentDraft {
        var title = fallbackTitle
        var blocks: [BlockDraft] = []
        var hasTakenTitle = false
        var previousLineWasBlank = true

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingTrailingWhitespace()
            if line.isBlank {
                previousLineWasBlank = true
                continue
            }
            defer { previousLineWasBlank = false }

            var block = self.block(from: line)

            // The first heading doubles as the document's name, but only when it leads the
            // file — a `# ` halfway down is a genuine heading.
            if !hasTakenTitle {
                hasTakenTitle = true
                if block.kind == .heading1 && blocks.isEmpty {
                    title = block.text
                    continue
                }
            }

            // Markdown viewers treat consecutive plain lines as one paragraph; matching
            // that keeps imported prose from exploding into one block per visual line.
            if block.kind == .paragraph, !previousLineWasBlank, var last = blocks.last, last.kind == .paragraph {
                last.text += " " + block.text
                blocks[blocks.count - 1] = last
                continue
            }

            block.indent = min(block.indent, MarkdownSyntax.maxIndent)
            blocks.append(block)
        }

        return DocumentDraft(title: title, blocks: blocks)
    }

    /// Parses one line in isolation. Also used by the editor to interpret pasted text.
    public static func block(from rawLine: String) -> BlockDraft {
        let (indent, line) = splitIndent(from: rawLine)

        if isDivider(line) {
            return BlockDraft(kind: .divider, text: "", indent: 0)
        }

        if let level = headingLevel(of: line) {
            let text = String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)
            return BlockDraft(kind: .heading(level: level), text: text, indent: 0)
        }

        if let (isChecked, body) = todoBody(of: line) {
            let (text, assignments) = extractAssignments(from: body)
            // With assignees present, the per-person marks are authoritative and the box
            // is just their summary; `isDoneSolo` only matters when nobody is assigned.
            return BlockDraft(
                kind: .todo,
                text: text,
                indent: indent,
                isDoneSolo: assignments.isEmpty && isChecked,
                assignments: assignments
            )
        }

        if let body = bulletBody(of: line) {
            return BlockDraft(kind: .bullet, text: body, indent: indent)
        }

        return BlockDraft(kind: .paragraph, text: line.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Line shapes

    private static func splitIndent(from line: String) -> (indent: Int, rest: String) {
        var spaces = 0
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " {
                spaces += 1
            } else if character == "\t" {
                spaces += MarkdownSyntax.indentUnit.count
            } else {
                break
            }
            index = line.index(after: index)
        }
        return (spaces / MarkdownSyntax.indentUnit.count, String(line[index...]))
    }

    private static func isDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" } || trimmed.allSatisfy { $0 == "*" }
            || trimmed.allSatisfy { $0 == "_" }
    }

    private static func headingLevel(of line: String) -> Int? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...3).contains(level) else { return nil }
        let afterHashes = line.index(line.startIndex, offsetBy: level)
        guard afterHashes < line.endIndex, line[afterHashes] == " " else { return nil }
        return level
    }

    /// Matches `- [ ] body`, `- [x] body`, and the `*` / `+` bullet variants.
    private static func todoBody(of line: String) -> (isChecked: Bool, body: String)? {
        guard let afterMarker = listMarkerEnd(of: line) else { return nil }
        let rest = line[afterMarker...]
        guard rest.count >= 3, rest.first == "[" else { return nil }

        let boxCharacter = rest[rest.index(rest.startIndex, offsetBy: 1)]
        let closing = rest[rest.index(rest.startIndex, offsetBy: 2)]
        guard closing == "]" else { return nil }

        let isChecked: Bool
        switch boxCharacter {
        case " ": isChecked = false
        case "x", "X", "✓": isChecked = true
        default: return nil
        }

        let body = rest.dropFirst(3)
        return (isChecked, String(body).trimmingCharacters(in: .whitespaces))
    }

    private static func bulletBody(of line: String) -> String? {
        guard let afterMarker = listMarkerEnd(of: line) else { return nil }
        return String(line[afterMarker...]).trimmingCharacters(in: .whitespaces)
    }

    /// Index just past a `- ` / `* ` / `+ ` list marker, if the line has one.
    private static func listMarkerEnd(of line: String) -> String.Index? {
        guard let first = line.first, "-*+".contains(first) else { return nil }
        let second = line.index(after: line.startIndex)
        guard second < line.endIndex, line[second] == " " else { return nil }
        return line.index(after: second)
    }

    // MARK: - Mentions

    /// Peels `@mentions` off the end of a todo line.
    ///
    /// Returns the remaining text and the assignments in written order.
    public static func extractAssignments(from body: String) -> (text: String, assignments: [AssignmentDraft]) {
        var remainder = body.trimmingTrailingWhitespace()
        var collected: [AssignmentDraft] = []

        while let mention = trailingMention(in: remainder) {
            collected.append(AssignmentDraft(person: PersonRef(name: mention.name), isDone: mention.isDone))
            remainder = String(remainder[remainder.startIndex..<mention.start]).trimmingTrailingWhitespace()
        }

        return (remainder, Array(collected.reversed()))
    }

    private struct Mention {
        let name: String
        let isDone: Bool
        let start: String.Index
    }

    private static func trailingMention(in text: String) -> Mention? {
        guard !text.isEmpty else { return nil }

        var end = text.endIndex
        var isDone = false
        if text[text.index(before: end)] == MarkdownSyntax.doneMarker {
            isDone = true
            end = text.index(before: end)
            guard end > text.startIndex else { return nil }
        }

        let name: String
        let sigilIndex: String.Index

        if text[text.index(before: end)] == "]" {
            let closing = text.index(before: end)
            guard let opening = text[text.startIndex..<closing].lastIndex(of: "["),
                  opening > text.startIndex,
                  text[text.index(before: opening)] == MarkdownSyntax.mentionSigil
            else { return nil }
            sigilIndex = text.index(before: opening)
            name = String(text[text.index(after: opening)..<closing])
        } else {
            var start = end
            while start > text.startIndex {
                let candidate = text.index(before: start)
                if MarkdownSyntax.isNameTerminator(text[candidate]) { break }
                start = candidate
            }
            guard start > text.startIndex,
                  text[text.index(before: start)] == MarkdownSyntax.mentionSigil,
                  start < end
            else { return nil }
            sigilIndex = text.index(before: start)
            name = String(text[start..<end])
        }

        // `teacher@school` is an address, not an assignment: a mention has to stand alone.
        if sigilIndex > text.startIndex {
            guard text[text.index(before: sigilIndex)].isWhitespace else { return nil }
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        return Mention(name: trimmedName, isDone: isDone, start: sigilIndex)
    }
}
