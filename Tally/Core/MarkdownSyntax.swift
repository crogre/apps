import Foundation

/// The shared vocabulary of the markdown format, so the serializer and the parser cannot
/// drift apart.
///
/// The format is deliberately plain GitHub-flavored markdown with one extension: people
/// are mentioned with `@` at the end of a todo line, and a person who has ticked their own
/// box carries a trailing check mark.
///
/// ```markdown
/// # Trip to Åre
///
/// ## Kids
/// - [ ] 2 pairs of socks @Alma✓ @Vidar
/// - [x] Toothbrush @Alma
/// - [ ] Sunscreen
/// ```
///
/// The leading `[ ]` / `[x]` box reflects the *whole* item, so it only reads `[x]` once
/// every assignee is done. That keeps the file meaningful in any markdown viewer while
/// still carrying the per-person detail.
public enum MarkdownSyntax {
    public static let doneMarker: Character = "✓"
    public static let mentionSigil: Character = "@"
    public static let indentUnit = "  "
    public static let maxIndent = 6

    /// Characters that end a bare (unbracketed) `@mention`.
    static func isNameTerminator(_ character: Character) -> Bool {
        character.isWhitespace
            || character == mentionSigil
            || character == "["
            || character == "]"
            || character == doneMarker
    }

    /// A bare mention is only used when the name survives a round trip without brackets.
    static func needsBrackets(_ name: String) -> Bool {
        name.isEmpty || name.contains(where: isNameTerminator)
    }

    /// Renders `@Alma`, `@[Alma Svensson]`, or either of those with a trailing check mark.
    static func mention(for person: PersonRef, isDone: Bool) -> String {
        // A literal `]` would terminate the bracketed form early. Real names do not
        // contain one, so substituting is safer than inventing an escape syntax.
        let name = person.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "]", with: ")")
        let body = needsBrackets(name) ? "\(mentionSigil)[\(name)]" : "\(mentionSigil)\(name)"
        return isDone ? body + String(doneMarker) : body
    }
}
