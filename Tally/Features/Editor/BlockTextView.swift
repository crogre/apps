import SwiftUI
import UIKit

/// The editable line of a block.
///
/// SwiftUI's `TextField` cannot report where the caret is or tell you that backspace was
/// pressed on an empty selection, and both are needed for a Notes-style editor: return
/// splits a line at the caret, backspace at the very start folds the line into the one
/// above. So this is a `UITextView` bridge — the one piece of UIKit in the app.
struct BlockTextView: UIViewRepresentable {

    @Binding var text: String
    let kind: BlockKind
    let isCompleted: Bool
    let placeholder: String

    /// Which block currently owns the keyboard. Driving first responder from a single
    /// piece of state avoids two rows fighting over it.
    @Binding var focusedBlockID: UUID?
    let blockID: UUID

    /// Set after a merge so the caret lands at the join rather than at the end.
    @Binding var pendingCaretOffset: Int?

    /// Return pressed; the offset is where the caret was.
    var onReturn: (Int) -> Void
    /// Backspace pressed with the caret at position 0.
    var onBackspaceAtStart: () -> Void
    /// Multi-line text arrived (usually a paste) and should become several blocks.
    var onInsertMultiline: (String, Int) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        // Growing to fit is what lets the row sit inside a List and wrap naturally.
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.returnKeyType = .default
        context.coordinator.apply(text: text, kind: kind, isCompleted: isCompleted, to: textView)
        context.coordinator.updatePlaceholder(placeholder, on: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text || context.coordinator.renderedKind != kind
            || context.coordinator.renderedCompleted != isCompleted {
            let selection = textView.selectedRange
            context.coordinator.apply(text: text, kind: kind, isCompleted: isCompleted, to: textView)
            let limit = (textView.text as NSString).length
            textView.selectedRange = NSRange(
                location: min(selection.location, limit),
                length: min(selection.length, max(0, limit - min(selection.location, limit)))
            )
        }

        context.coordinator.updatePlaceholder(placeholder, on: textView)

        if let offset = pendingCaretOffset, focusedBlockID == blockID {
            let limit = (textView.text as NSString).length
            textView.selectedRange = NSRange(location: min(offset, limit), length: 0)
            DispatchQueue.main.async { pendingCaretOffset = nil }
        }

        // Nudging first responder inside `updateUIView` has to be deferred or UIKit and
        // SwiftUI end up mutating state during the same layout pass.
        if focusedBlockID == blockID, !textView.isFirstResponder {
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        } else if focusedBlockID != blockID, textView.isFirstResponder {
            DispatchQueue.main.async { textView.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, uiView.font?.lineHeight ?? 20))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var renderedKind: BlockKind?
        var renderedCompleted: Bool?
        private var placeholderLabel: UILabel?

        init(parent: BlockTextView) {
            self.parent = parent
        }

        func apply(text: String, kind: BlockKind, isCompleted: Bool, to textView: UITextView) {
            textView.attributedText = MarkdownHighlighter.attributedText(
                for: text,
                kind: kind,
                isCompleted: isCompleted
            )
            textView.typingAttributes = [
                .font: MarkdownHighlighter.font(for: kind),
                .foregroundColor: isCompleted ? UIColor.secondaryLabel : UIColor.label,
            ]
            renderedKind = kind
            renderedCompleted = isCompleted
            refreshPlaceholderVisibility(on: textView)
        }

        func updatePlaceholder(_ text: String, on textView: UITextView) {
            if placeholderLabel == nil {
                let label = UILabel()
                label.textColor = .placeholderText
                label.numberOfLines = 1
                label.translatesAutoresizingMaskIntoConstraints = false
                textView.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
                    label.topAnchor.constraint(equalTo: textView.topAnchor),
                ])
                placeholderLabel = label
            }
            placeholderLabel?.text = text
            placeholderLabel?.font = MarkdownHighlighter.font(for: parent.kind)
            refreshPlaceholderVisibility(on: textView)
        }

        private func refreshPlaceholderVisibility(on textView: UITextView) {
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }

        // MARK: - UITextViewDelegate

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            // Backspace with nothing selected at the very start of the line.
            if replacement.isEmpty, range.length == 0, range.location == 0 {
                parent.onBackspaceAtStart()
                return false
            }

            if replacement == "\n" {
                parent.onReturn(range.location)
                return false
            }

            if replacement.contains("\n") {
                parent.onInsertMultiline(replacement, range.location)
                return false
            }

            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let selection = textView.selectedRange
            parent.text = textView.text
            // Re-styling replaces the attributed string, which resets the caret.
            apply(
                text: textView.text,
                kind: parent.kind,
                isCompleted: parent.isCompleted,
                to: textView
            )
            textView.selectedRange = selection
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if parent.focusedBlockID != parent.blockID {
                parent.focusedBlockID = parent.blockID
            }
        }
    }
}
