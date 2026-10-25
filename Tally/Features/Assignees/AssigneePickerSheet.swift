import SwiftData
import SwiftUI

/// "Who is this for?" — shown when a to-do is created and whenever you tap the chips.
///
/// Existing people are listed most-recently-used first so the answer is usually one tap;
/// typing a name that does not exist yet offers to create it.
struct AssigneePickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Person.lastUsedAt, order: .reverse) private var people: [Person]

    /// Who is already on the item.
    let initialSelection: [Person]
    /// Used when the item has nobody yet — the set most recently used in this note.
    var fallbackSelection: [Person] = []
    let onDone: ([Person]) -> Void

    @State private var selectedIDs: [UUID] = []
    @State private var searchText = ""
    @State private var hasPrimed = false
    /// Who sits in the top section. Fixed when the sheet opens so ticking someone never
    /// moves rows around under your finger.
    @State private var pinnedIDs: [UUID] = []

    var body: some View {
        NavigationStack {
            List {
                if !pinnedPeople.isEmpty {
                    Section(initialSelection.isEmpty ? "Last used in this note" : "Assigned") {
                        ForEach(pinnedPeople) { person in
                            personRow(person, isSelected: selectedIDs.contains(person.id))
                        }
                    }
                }

                if creatableName != nil || !otherPeople.isEmpty || people.isEmpty {
                    Section(pinnedIDs.isEmpty ? "People" : "Everyone else") {
                        if let name = creatableName {
                            Button {
                                create(named: name)
                            } label: {
                                Label("Create “\(name)”", systemImage: "person.badge.plus")
                            }
                        }

                        ForEach(otherPeople) { person in
                            personRow(person, isSelected: selectedIDs.contains(person.id))
                        }

                        if people.isEmpty && creatableName == nil {
                            Text("Type a name to add the first person.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name")
            .navigationTitle("Assign to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone(selectedPeople)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .pickerSheet()
        .onAppear(perform: prime)
    }

    private func personRow(_ person: Person, isSelected: Bool) -> some View {
        Button {
            toggle(person)
        } label: {
            HStack(spacing: 10) {
                PersonAvatar(person: person, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: person.name)
                        .foregroundStyle(.primary)
                    if person.openAssignmentCount > 0 {
                        Text("^[\(person.openAssignmentCount) open item](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Selection

    private var selectedPeople: [Person] {
        selectedIDs.compactMap { id in people.first { $0.id == id } }
    }

    private var matchingPeople: [Person] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return people }
        return people.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var pinnedPeople: [Person] {
        let matching = Set(matchingPeople.map(\.id))
        return pinnedIDs.compactMap { id in people.first { $0.id == id } }
            .filter { matching.contains($0.id) }
    }

    private var otherPeople: [Person] {
        matchingPeople.filter { !pinnedIDs.contains($0.id) }
    }

    /// The typed name, when it is not already somebody's name.
    private var creatableName: String? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let key = PersonRef(name: query).matchKey
        guard !people.contains(where: { PersonRef(name: $0.name).matchKey == key }) else { return nil }
        return query
    }

    private func prime() {
        guard !hasPrimed else { return }
        hasPrimed = true
        let source = initialSelection.isEmpty ? fallbackSelection : initialSelection
        selectedIDs = source.map(\.id)
        pinnedIDs = selectedIDs
    }

    private func toggle(_ person: Person) {
        if let index = selectedIDs.firstIndex(of: person.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(person.id)
        }
    }

    private func create(named name: String) {
        guard let person = PersonStore(context: context).findOrCreate(named: name) else { return }
        selectedIDs.append(person.id)
        searchText = ""
    }
}
