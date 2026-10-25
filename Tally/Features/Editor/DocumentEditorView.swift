import SwiftData
import SwiftUI

struct DocumentEditorView: View {
    @Bindable var document: Document

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKey.promptForAssignees) private var promptModeRaw = AssigneePromptMode.firstInNote.rawValue

    @State private var focusedBlockID: UUID?
    @State private var pendingCaretOffset: Int?
    /// One piece of state for every sheet: stacking several `.sheet` modifiers on the same
    /// view is a well-known way to end up with one of them silently never presenting.
    @State private var sheet: EditorSheet?
    /// The line that had the keyboard when a sheet opened. The editor lets go of the
    /// keyboard while a sheet is up — otherwise it covers the sheet and keeps typing into
    /// the note — and hands it back here once the sheet closes.
    @State private var focusAfterSheet: UUID?

    /// The assignees most recently chosen in this note. New todos pick them up so a
    /// packing list where every item goes to both kids does not mean answering the same
    /// question twenty times.
    @State private var stickyAssignees: [Person] = []

    private var commands: EditorCommands {
        EditorCommands(document: document, context: context)
    }

    private var promptMode: AssigneePromptMode {
        AssigneePromptMode(rawValue: promptModeRaw) ?? .firstInNote
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                titleField
                ForEach(document.orderedBlocks) { block in
                    row(for: block)
                        .id(block.id)
                }
                .onMove { commands.move(fromOffsets: $0, toOffset: $1) }
                .onDelete(perform: deleteBlocks)

                tapToAppendSpacer
            }
            // The list only scrolls far enough to show the caret, which leaves a to-do's
            // chips under the keyboard. Bring the whole row into view instead.
            .onChange(of: focusedBlockID) { _, id in reveal(id, with: proxy) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                reveal(focusedBlockID, with: proxy)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle(document.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $sheet, onDismiss: restoreFocusAfterSheet) { destination in
            switch destination {
            case let .assignees(block):
                AssigneePickerSheet(
                    initialSelection: block.people,
                    fallbackSelection: stickyAssignees
                ) { people in
                    applyAssignees(people, to: block)
                }
            case let .completer(block):
                CompleterSheet(block: block)
            case .template:
                NewFromDocumentSheet(source: document) { _ in dismiss() }
            case .peopleOrder:
                NotePeopleOrderSheet(document: document)
            }
        }
        .onAppear(perform: primeStickyAssignees)
    }

    private enum EditorSheet: Identifiable {
        case assignees(Block)
        case completer(Block)
        case template
        case peopleOrder

        var id: String {
            switch self {
            case let .assignees(block): return "assignees-\(block.id)"
            case let .completer(block): return "completer-\(block.id)"
            case .template: return "template"
            case .peopleOrder: return "peopleOrder"
            }
        }
    }

    // MARK: - Rows

    private var titleField: some View {
        TextField("Title", text: $document.title)
            .font(.largeTitle.bold())
            .textInputAutocapitalization(.sentences)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .onChange(of: document.title) { _, _ in document.touch() }
            .submitLabel(.next)
            .onSubmit { focusFirstBlock() }
    }

    private func row(for block: Block) -> some View {
        BlockRow(
            block: block,
            focusedBlockID: $focusedBlockID,
            pendingCaretOffset: $pendingCaretOffset,
            onReturn: { offset in handleReturn(on: block, at: offset) },
            onBackspaceAtStart: { handleBackspaceAtStart(on: block) },
            onInsertMultiline: { text, offset in handleMultiline(text, on: block, at: offset) },
            onTextChange: { text in applyTypingShortcut(to: block, text: text) },
            onTapCheckbox: { handleCheckboxTap(on: block) },
            onEditAssignees: { present(.assignees(block)) }
        )
    }

    /// Empty space under the last line: tapping it starts a new paragraph, the way a page
    /// of paper works.
    private var tapToAppendSpacer: some View {
        Color.clear
            .frame(height: 120)
            .contentShape(Rectangle())
            .listRowSeparator(.hidden)
            .onTapGesture {
                if let last = document.orderedBlocks.last, last.text.isEmpty, last.kind == .paragraph {
                    focusedBlockID = last.id
                } else {
                    let new = commands.append()
                    focusedBlockID = new.id
                }
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                DocumentActionsMenu(
                    document: document,
                    onUseAsTemplate: { present(.template) },
                    onOrderPeople: { present(.peopleOrder) },
                    onDelete: {
                        context.delete(document)
                        dismiss()
                    }
                )
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }

        ToolbarItemGroup(placement: .keyboard) {
            if let block = focusedBlock {
                keyboardAccessory(for: block)
            }
        }
    }

    @ViewBuilder
    private func keyboardAccessory(for block: Block) -> some View {
        Button {
            commands.setKind(block.kind == .todo ? .paragraph : .todo, on: block)
            if block.kind == .todo { applyStickyAssignees(to: block) }
        } label: {
            Image(systemName: "checklist")
        }
        .accessibilityLabel("To-do")

        Button {
            commands.setKind(block.kind == .bullet ? .paragraph : .bullet, on: block)
        } label: {
            Image(systemName: "list.bullet")
        }
        .accessibilityLabel("Bullet")

        Menu {
            Button("Heading") { commands.setKind(.heading1, on: block) }
            Button("Subheading") { commands.setKind(.heading2, on: block) }
            Button("Small heading") { commands.setKind(.heading3, on: block) }
            Button("Body") { commands.setKind(.paragraph, on: block) }
            Divider()
            Button("Divider") { commands.setKind(.divider, on: block) }
        } label: {
            Image(systemName: "textformat")
        }
        .accessibilityLabel("Text style")

        Button {
            commands.adjustIndent(block, by: -1)
        } label: {
            Image(systemName: "decrease.indent")
        }
        .disabled(!block.kind.acceptsIndent || block.indent == 0)
        .accessibilityLabel("Outdent")

        Button {
            commands.adjustIndent(block, by: 1)
        } label: {
            Image(systemName: "increase.indent")
        }
        .disabled(!block.kind.acceptsIndent)
        .accessibilityLabel("Indent")

        Spacer()

        Button {
            present(.assignees(block))
        } label: {
            Image(systemName: "person.badge.plus")
        }
        .disabled(block.kind != .todo)
        .accessibilityLabel("Assign people")

        Button("Done") { focusedBlockID = nil }
    }

    // MARK: - Editing

    private var focusedBlock: Block? {
        guard let focusedBlockID else { return nil }
        return document.orderedBlocks.first { $0.id == focusedBlockID }
    }

    private func reveal(_ id: UUID?, with proxy: ScrollViewProxy) {
        guard let id else { return }
        // Wait for the row to exist and the keyboard inset to land before scrolling.
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(id) }
        }
    }

    private func focusFirstBlock() {
        focusedBlockID = document.orderedBlocks.first?.id
    }

    private func handleReturn(on block: Block, at offset: Int) {
        // Return on an empty list item steps back out instead of making another one.
        if commands.outdentOrPlain(block) { return }

        let new = commands.split(block, at: offset)
        if new.kind == .todo {
            applyStickyAssignees(to: new)
        }
        focusedBlockID = new.id
        pendingCaretOffset = 0

        // Ask who the item just finished belongs to, if it does not say yet.
        maybePromptForAssignees(on: block)
    }

    private func handleBackspaceAtStart(on block: Block) {
        guard let result = commands.mergeBackward(block) else { return }
        focusedBlockID = result.target.id
        pendingCaretOffset = result.caretOffset
    }

    private func handleMultiline(_ inserted: String, on block: Block, at offset: Int) {
        let characters = Array(block.text)
        let safeOffset = max(0, min(offset, characters.count))
        let tail = String(characters[safeOffset...])
        let lines = inserted.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        block.text = String(characters[..<safeOffset]) + lines[0]

        var anchor = block
        for line in lines.dropFirst() {
            let draft = MarkdownParser.block(from: line)
            let new = commands.insert(
                kind: draft.kind,
                text: draft.text,
                indent: draft.indent,
                after: anchor
            )
            new.isDoneSolo = draft.isDoneSolo
            if !draft.assignments.isEmpty {
                let store = PersonStore(context: context)
                let people = draft.assignments.compactMap { store.resolve($0.person) }
                commands.setAssignees(people, on: new)
                for assignmentDraft in draft.assignments where assignmentDraft.isDone {
                    if let person = store.person(named: assignmentDraft.person.name) {
                        new.assignment(for: person)?.completedAt = Date.now
                    }
                }
            }
            anchor = new
        }

        let caret = anchor.text.count
        anchor.text += tail
        focusedBlockID = anchor.id
        pendingCaretOffset = caret
    }

    private func applyTypingShortcut(to block: Block, text: String) {
        guard let match = TypingShortcut.match(text: text, currentKind: block.kind) else { return }
        block.text = match.remainingText
        commands.setKind(match.kind, on: block)
        if match.kind == .todo {
            applyStickyAssignees(to: block)
        }
        pendingCaretOffset = match.remainingText.count
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let ordered = document.orderedBlocks
        for index in offsets where ordered.indices.contains(index) {
            commands.delete(ordered[index])
        }
    }

    // MARK: - Ticking

    private func handleCheckboxTap(on block: Block) {
        if block.needsCompleterPrompt {
            // More than one person is on the item, so "who finished it?" is a real question.
            present(.completer(block))
            return
        }

        let wasComplete = block.completion.isComplete
        block.toggleCompleted()
        document.touch()
        if wasComplete {
            Haptics.untick()
        } else {
            Haptics.itemCompleted()
        }
    }

    // MARK: - Assignees

    private func applyAssignees(_ people: [Person], to block: Block) {
        commands.setAssignees(people, on: block)
        stickyAssignees = people

        // The empty line created just before the sheet opened should inherit the answer too.
        // It gave up the keyboard for the sheet, so it is the one waiting in `focusAfterSheet`.
        let pendingID = focusAfterSheet ?? focusedBlockID
        if let focused = document.orderedBlocks.first(where: { $0.id == pendingID }),
           focused.id != block.id,
           focused.kind == .todo,
           focused.orderedAssignments.isEmpty {
            commands.setAssignees(people, on: focused)
        }
    }

    private func applyStickyAssignees(to block: Block) {
        guard block.kind == .todo, block.orderedAssignments.isEmpty, !stickyAssignees.isEmpty else { return }
        commands.setAssignees(stickyAssignees, on: block)
    }

    private func maybePromptForAssignees(on block: Block) {
        guard block.kind == .todo,
              !block.text.isBlank,
              block.orderedAssignments.isEmpty
        else { return }

        switch promptMode {
        case .never:
            return
        case .firstInNote:
            guard stickyAssignees.isEmpty else { return }
        case .always:
            break
        }

        present(.assignees(block))
    }

    // MARK: - Sheets

    private func present(_ destination: EditorSheet) {
        if focusedBlockID != nil {
            focusAfterSheet = focusedBlockID
            focusedBlockID = nil
            // Resign now rather than on the next update: UIKit gives the keyboard back to
            // whatever held it when the sheet was presented, which would be the wrong line.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        sheet = destination
    }

    private func restoreFocusAfterSheet() {
        guard let id = focusAfterSheet else { return }
        focusAfterSheet = nil
        if document.orderedBlocks.contains(where: { $0.id == id }) {
            focusedBlockID = id
        }
    }

    /// Opening a note that already has assignees should not start from a blank slate — the
    /// most recently used set in this note becomes the sticky one.
    private func primeStickyAssignees() {
        guard stickyAssignees.isEmpty else { return }
        stickyAssignees = document.todoBlocks.last(where: { !$0.people.isEmpty })?.people ?? []
    }
}

/// How eagerly the app asks who a new todo belongs to.
enum AssigneePromptMode: String, CaseIterable, Identifiable {
    /// Ask every time a todo is finished without assignees.
    case always
    /// Ask for the first one, then reuse that answer for the rest of the note.
    case firstInNote
    /// Never ask; assign from the chip row when you want to.
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Every to-do"
        case .firstInNote: return "First in a note"
        case .never: return "Never"
        }
    }

    var explanation: String {
        switch self {
        case .always: return "Ask who each new to-do is for."
        case .firstInNote: return "Ask once, then reuse that answer for the rest of the note."
        case .never: return "Assign people from the chips under an item instead."
        }
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let document = try! container.mainContext.fetch(FetchDescriptor<Document>()).first!
    return NavigationStack {
        DocumentEditorView(document: document)
    }
    .modelContainer(container)
}
