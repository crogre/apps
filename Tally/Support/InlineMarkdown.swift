import SwiftUI

/// Renders the inline markdown stored in a block's text.
///
/// The editor is a hybrid: the line you are typing in shows its raw source, every other
/// line is rendered. This is what turns `**socks**` into **socks** the moment you move on.
enum InlineMarkdown {
    static func attributed(_ source: String) -> AttributedString {
        guard !source.isEmpty else { return AttributedString() }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            // Inline only: a stray `#` or `-` in the middle of a line is text, because the
            // block already decides what kind of line this is.
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
