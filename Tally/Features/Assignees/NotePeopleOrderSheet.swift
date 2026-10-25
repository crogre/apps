import SwiftUI

/// The order people appear in within one note. Off, the note follows the global order from
/// People; on, dragging here sets an order just for this note. Changes apply as you make
/// them, so the note behind the sheet rearranges along with you.
struct NotePeopleOrderSheet: View {
    @Bindable var document: Document
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Own order for this note", isOn: hasOwnOrder)
                } footer: {
                    Text(document.peopleOrderOverride == nil
                         ? "Follows the order set in People."
                         : "Drag to reorder. People added later go after these, in the global order.")
                }

                Section {
                    ForEach(document.distinctPeople) { person in
                        HStack(spacing: 10) {
                            PersonAvatar(person: person, size: 28)
                            Text(verbatim: person.name)
                        }
                    }
                    .onMove(perform: move)
                    .moveDisabled(document.peopleOrderOverride == nil)
                }
            }
            .environment(\.editMode, .constant(document.peopleOrderOverride == nil ? .inactive : .active))
            .navigationTitle("Order of people")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Turning it on starts from the order the note shows now, so nothing jumps.
    private var hasOwnOrder: Binding<Bool> {
        Binding(
            get: { document.peopleOrderOverride != nil },
            set: { isOn in
                document.peopleOrderOverride = isOn ? document.distinctPeople.map(\.id) : nil
                document.touch()
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = document.distinctPeople.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        document.peopleOrderOverride = ids
        document.touch()
    }
}
