import SwiftUI

/// One line of the document.
struct BlockRow: View {
    @Bindable var block: Block

    @Binding var focusedBlockID: UUID?
    @Binding var pendingCaretOffset: Int?

    var onReturn: (Int) -> Void
    var onBackspaceAtStart: () -> Void
    var onInsertMultiline: (String, Int) -> Void
    var onTextChange: (String) -> Void
    var onTapCheckbox: () -> Void
    var onEditAssignees: () -> Void

    private var isFocused: Bool { focusedBlockID == block.id }

    var body: some View {
        if block.kind == .divider {
            dividerRow
        } else {
            textRow
        }
    }

    private var dividerRow: some View {
        Divider()
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { focusedBlockID = block.id }
            .accessibilityLabel("Divider")
    }

    private var textRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear
                .frame(width: CGFloat(block.indent) * 18, height: 1)

            marker

            VStack(alignment: .leading, spacing: 4) {
                BlockTextView(
                    text: $block.text,
                    kind: block.kind,
                    isCompleted: block.kind == .todo && block.completion.isComplete,
                    placeholder: isFocused ? placeholder : "",
                    focusedBlockID: $focusedBlockID,
                    blockID: block.id,
                    pendingCaretOffset: $pendingCaretOffset,
                    onReturn: onReturn,
                    onBackspaceAtStart: onBackspaceAtStart,
                    onInsertMultiline: onInsertMultiline
                )

                if block.kind == .todo {
                    assigneeRow
                }
            }
        }
        .padding(.vertical, verticalPadding)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .onChange(of: block.text) { _, newValue in onTextChange(newValue) }
    }

    @ViewBuilder
    private var marker: some View {
        switch block.kind {
        case .todo:
            Button(action: onTapCheckbox) {
                Group {
                    if block.orderedAssignments.isEmpty {
                        Image(systemName: block.completion.symbolName)
                            .font(.system(size: 20))
                            .foregroundStyle(block.completion.isComplete ? Color.accentColor : .secondary)
                    } else {
                        AssigneePieCheckbox(assignments: block.orderedAssignments)
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityCheckboxLabel)
            .accessibilityHint(
                block.needsCompleterPrompt
                    ? "Opens a list of the people assigned so you can tick one of them"
                    : "Toggles this item"
            )
            // Keeps the box lined up with the first line of text rather than its centre.
            .padding(.top, 1)

        case .bullet:
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
                .frame(width: 26, height: 26)
                .padding(.top, 1)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var assigneeRow: some View {
        if !block.orderedAssignments.isEmpty {
            Button(action: onEditAssignees) { chips }
                .buttonStyle(.plain)
                .accessibilityLabel("Assignees")
                .accessibilityHint("Change who this item is assigned to")
        } else if isFocused {
            // Only offered on the line being edited, so a long list is not littered with
            // buttons for items nobody is on.
            Button(action: onEditAssignees) {
                Label("Assign…", systemImage: "person.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(block.orderedAssignments) { assignment in
                if let person = assignment.person {
                    PersonChip(person: person, isDone: assignment.isDone)
                }
            }
            if let progress = block.completion.progressText {
                Text(verbatim: progress)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityCheckboxLabel: String {
        let completion = block.completion
        if completion.isUnassigned {
            return completion.isComplete ? "Completed" : "Not completed"
        }
        return "\(completion.doneCount) of \(completion.totalCount) done"
    }

    private var placeholder: String {
        switch block.kind {
        case .heading1, .heading2, .heading3: return "Heading"
        case .todo: return "To-do"
        case .bullet: return "List item"
        default: return "Start writing…"
        }
    }

    private var verticalPadding: CGFloat {
        switch block.kind {
        case .heading1: return 10
        case .heading2, .heading3: return 8
        default: return 3
        }
    }
}
