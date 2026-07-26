import Foundation

/// Markdown shortcuts recognised as you type: `# ` becomes a heading, `- ` a bullet,
/// `[] ` a todo. The prefix is swallowed and the block changes kind, the way Notes and
/// most markdown-ish editors behave.
public enum TypingShortcut {

    public struct Match: Equatable, Sendable {
        public let kind: BlockKind
        /// What the line should contain once the prefix has been eaten.
        public let remainingText: String

        public init(kind: BlockKind, remainingText: String) {
            self.kind = kind
            self.remainingText = remainingText
        }
    }

    /// Ordered longest-first so `- [] ` wins over `- `.
    private static let prefixes: [(prefix: String, kind: BlockKind)] = [
        ("- [ ] ", .todo),
        ("- [] ", .todo),
        ("* [ ] ", .todo),
        ("* [] ", .todo),
        ("[ ] ", .todo),
        ("[] ", .todo),
        ("### ", .heading3),
        ("## ", .heading2),
        ("# ", .heading1),
        ("- ", .bullet),
        ("* ", .bullet),
        ("+ ", .bullet),
    ]

    /// Checks the freshly typed text of a block for a shortcut.
    ///
    /// Only plain paragraphs and bullets convert; once a line is already a heading or a
    /// todo, a literal `# ` in the middle of writing is just text.
    public static func match(text: String, currentKind: BlockKind) -> Match? {
        guard currentKind == .paragraph || currentKind == .bullet else { return nil }

        if text == "---" || text == "***" {
            return Match(kind: .divider, remainingText: "")
        }

        for (prefix, kind) in prefixes where text.hasPrefix(prefix) {
            guard kind != currentKind else { continue }
            // A bullet should be able to become a todo, but not the other way round via
            // a `- ` the user typed inside an existing bullet.
            if currentKind == .bullet && kind == .bullet { continue }
            return Match(kind: kind, remainingText: String(text.dropFirst(prefix.count)))
        }

        return nil
    }
}
