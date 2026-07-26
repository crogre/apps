import SwiftUI

/// "Who did it?" — the popup that appears when you tick an item that more than one person
/// is on.
///
/// "2 pairs of socks" assigned to both kids is two separate jobs, so each of them gets
/// their own box here and the item only counts as done once both are ticked.
struct CompleterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var block: Block

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(block.orderedAssignments) { assignment in
                        if let person = assignment.person {
                            row(for: assignment, person: person)
                        }
                    }
                } header: {
                    Text(verbatim: block.text.isBlank ? "To-do" : block.text)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .padding(.bottom, 2)
                } footer: {
                    Text(footerText)
                }

                Section {
                    Button {
                        block.setCompleted(true)
                        Haptics.itemCompleted()
                        dismiss()
                    } label: {
                        Label("Mark all done", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(block.completion.isComplete)

                    Button {
                        block.setCompleted(false)
                        Haptics.untick()
                    } label: {
                        Label("Clear all", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(block.completion.doneCount == 0)
                }
            }
            .navigationTitle("Who did it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .pickerSheet()
    }

    private func row(for assignment: Assignment, person: Person) -> some View {
        Button {
            toggle(assignment)
        } label: {
            HStack(spacing: 10) {
                PersonAvatar(person: person, size: 30)
                Text(verbatim: person.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: assignment.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(assignment.isDone ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityValue(assignment.isDone ? "done" : "not done")
        .accessibilityAddTraits(assignment.isDone ? [.isSelected] : [])
    }

    // Typed as a key rather than a String so the inflection markup is actually applied.
    private var footerText: LocalizedStringKey {
        let completion = block.completion
        if completion.isComplete { return "Everyone is done." }
        let remaining = completion.totalCount - completion.doneCount
        return "^[\(remaining) person](inflect: true) still to go."
    }

    private func toggle(_ assignment: Assignment) {
        assignment.isDone.toggle()
        block.document?.touch()

        if block.completion.isComplete {
            Haptics.itemCompleted()
            // The question has been answered; getting out of the way is the whole point.
            dismiss()
        } else if assignment.isDone {
            Haptics.tick()
        } else {
            Haptics.untick()
        }
    }
}
