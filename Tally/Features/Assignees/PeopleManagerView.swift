import SwiftData
import SwiftUI

/// The people you assign things to.
struct PeopleManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Person.lastUsedAt, order: .reverse) private var people: [Person]

    @State private var newName = ""
    @State private var personPendingDeletion: Person?
    @State private var renaming: Person?
    @State private var renamedTo = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a person", text: $newName)
                        .textInputAutocapitalization(.words)
                        .onSubmit(addPerson)
                    Button("Add", action: addPerson)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section {
                if people.isEmpty {
                    Text("Nobody yet. People are also created as you assign them to items.")
                        .foregroundStyle(.secondary)
                }
                ForEach(people) { person in
                    row(for: person)
                }
            }
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Rename person", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renamedTo)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let person = renaming {
                    let trimmed = renamedTo.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { person.name = trimmed }
                }
                renaming = nil
            }
        }
        .confirmationDialog(
            "Remove \(personPendingDeletion?.name ?? "")?",
            isPresented: Binding(
                get: { personPendingDeletion != nil },
                set: { if !$0 { personPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let person = personPendingDeletion {
                    PersonStore(context: context).delete(person)
                }
                personPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { personPendingDeletion = nil }
        } message: {
            if let person = personPendingDeletion {
                Text(deletionWarning(for: person))
            }
        }
    }

    /// Typed as a key rather than a String so the inflection markup is applied.
    private func deletionWarning(for person: Person) -> LocalizedStringKey {
        let count = PersonStore(context: context).impactOfDeleting(person)
        if count == 0 { return "\(person.name) is not assigned to anything." }
        return "^[\(count) item](inflect: true) will stay, but will no longer be assigned to \(person.name)."
    }

    private func subtitle(for person: Person) -> LocalizedStringKey {
        if person.openAssignmentCount == 0 { return "Nothing outstanding" }
        return "^[\(person.openAssignmentCount) open item](inflect: true)"
    }

    private func row(for person: Person) -> some View {
        HStack(spacing: 10) {
            PersonAvatar(person: person, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: person.name)
                Text(subtitle(for: person))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                person.colorSeed = (person.colorSeed + 1) % PersonPalette.colors.count
            } label: {
                Image(systemName: "paintpalette")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change colour for \(person.name)")
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                personPendingDeletion = person
            } label: {
                Label("Remove", systemImage: "trash")
            }
            Button {
                renaming = person
                renamedTo = person.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    private func addPerson() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        PersonStore(context: context).findOrCreate(named: trimmed)
        newName = ""
    }
}
