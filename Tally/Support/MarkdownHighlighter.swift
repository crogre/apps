import UIKit

/// Styles a block's raw markdown for display *while it is being edited*.
///
/// The delimiters stay visible but fade back, so `**socks**` reads as **socks** without
/// the text ever jumping around as you move the caret in and out of a span. That keeps the
/// editor a single always-editable text view instead of swapping between an editor and a
/// rendered label, which is where this kind of editor usually gets fragile.
enum MarkdownHighlighter {

    static func attributedText(for text: String, kind: BlockKind, isCompleted: Bool = false) -> NSAttributedString {
        let baseFont = font(for: kind)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: isCompleted ? UIColor.secondaryLabel : UIColor.label,
            ]
        )
        if isCompleted {
            result.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: NSRange(location: 0, length: result.length)
            )
        }

        var claimed: [NSRange] = []

        apply(Patterns.code, to: result, claimed: &claimed) { range, content in
            result.addAttribute(.font, value: monospaced(baseFont), range: content)
            dim(result, range: range, content: content)
        }
        apply(Patterns.bold, to: result, claimed: &claimed) { range, content in
            result.addAttribute(.font, value: baseFont.withTraits(.traitBold), range: content)
            dim(result, range: range, content: content)
        }
        apply(Patterns.italicUnderscore, to: result, claimed: &claimed) { range, content in
            result.addAttribute(.font, value: baseFont.withTraits(.traitItalic), range: content)
            dim(result, range: range, content: content)
        }
        apply(Patterns.italicAsterisk, to: result, claimed: &claimed) { range, content in
            result.addAttribute(.font, value: baseFont.withTraits(.traitItalic), range: content)
            dim(result, range: range, content: content)
        }

        return result
    }

    static func font(for kind: BlockKind) -> UIFont {
        switch kind {
        case .heading1: return preferred(.title1, weight: .bold)
        case .heading2: return preferred(.title2, weight: .semibold)
        case .heading3: return preferred(.title3, weight: .semibold)
        default: return UIFont.preferredFont(forTextStyle: .body)
        }
    }

    // MARK: - Internals

    private enum Patterns {
        static let code = try? NSRegularExpression(pattern: "`([^`\n]+)`")
        static let bold = try? NSRegularExpression(pattern: "\\*\\*([^\n]+?)\\*\\*")
        static let italicUnderscore = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_])_([^_\n]+?)_(?![A-Za-z0-9_])")
        static let italicAsterisk = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)([^*\n]+?)\\*(?!\\*)")
    }

    private static func apply(
        _ expression: NSRegularExpression?,
        to string: NSMutableAttributedString,
        claimed: inout [NSRange],
        body: (_ full: NSRange, _ content: NSRange) -> Void
    ) {
        guard let expression else { return }
        let whole = NSRange(location: 0, length: string.length)
        let claimedSnapshot = claimed

        for match in expression.matches(in: string.string, range: whole) where match.numberOfRanges > 1 {
            let full = match.range
            // Nested styling is not worth the complexity; first pattern to claim a span wins.
            guard !claimedSnapshot.contains(where: { NSIntersectionRange($0, full).length > 0 }) else { continue }
            claimed.append(full)
            body(full, match.range(at: 1))
        }
    }

    /// Fades the `**` / `_` / `` ` `` characters without removing them.
    private static func dim(_ string: NSMutableAttributedString, range full: NSRange, content: NSRange) {
        let leading = NSRange(location: full.location, length: content.location - full.location)
        let trailingStart = content.location + content.length
        let trailing = NSRange(location: trailingStart, length: full.location + full.length - trailingStart)
        for delimiter in [leading, trailing] where delimiter.length > 0 {
            string.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: delimiter)
        }
    }

    private static func preferred(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    private static func monospaced(_ font: UIFont) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular)
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let combined = fontDescriptor.symbolicTraits.union(traits)
        guard let descriptor = fontDescriptor.withSymbolicTraits(combined) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
