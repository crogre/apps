import SwiftData
import SwiftUI

/// Start a new note from an existing one.
///
/// The packing list from the last trip becomes the packing list for this trip: same items,
/// same kids, nothing ticked. Optionally the people can be swapped out, so a list written
/// for one pair of kids can be pointed at somebody else.
struct NewFromDocumentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Person.lastUsedAt, order: .reverse) private var allPeople: [Person]

    let source: Document
    let onCreated: (Document) -> Void

    @State private var title = ""
    @State private var keepAssignees = true
    @State private var pinAsTemplate = false
    /// Source person id → replacement person id. Missing means "keep as is".
    @State private var replacements: [UUID: UUID] = [:]
    @State private var hasPrimed = false

    private var sourcePeople: [Person] { source.distinctPeople }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("New note")
                } footer: {
                    Text("Copies every line from “\(source.displayTitle)” with all boxes cleared.")
                }

                if !sourcePeople.isEmpty {
                    Section {
                        Toggle("Keep assignees", isOn: $keepAssignees.animation())
                    } footer: {
                        if keepAssignees {
                            Text("Each item stays assigned to the same people.")
                        } else {
                            Text("Items are copied without anyone assigned.")
                        }
                    }

                    if keepAssignees {
                        Section("Swap people") {
                            ForEach(sourcePeople) { person in
                                replacementRow(for: person)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Pin to Templates", isOn: $pinAsTemplate)
                } footer: {
                    Text("Pinned notes sit at the top of the list so they are easy to reuse.")
                }
            }
            .navigationTitle("New from note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create", action: create)
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear(perform: prime)
    }

    private func replacementRow(for person: Person) -> some View {
        Picker(selection: binding(for: person)) {
            Text("Keep \(person.name)").tag(person.id)
            ForEach(allPeople.filter { $0.id != person.id }) { candidate in
                Text(verbatim: candidate.name).tag(candidate.id)
            }
        } label: {
            HStack(spacing: 8) {
                PersonAvatar(person: person, size: 24)
                Text(verbatim: person.name)
            }
        }
    }

    private func binding(for person: Person) -> Binding<UUID> {
        Binding(
            get: { replacements[person.id] ?? person.id },
            set: { replacements[person.id] = $0 }
        )
    }

    private func prime() {
        guard !hasPrimed else { return }
        hasPrimed = true
        title = TemplateCloner.suggestedTitle(basedOn: source.draft, date: .now)
    }

    private func create() {
        var remap: [String: PersonRef] = [:]
        if keepAssignees {
            for person in sourcePeople {
                guard let replacementID = replacements[person.id], replacementID != person.id,
                      let replacement = allPeople.first(where: { $0.id == replacementID })
                else { continue }
                remap[PersonRef(name: person.name).matchKey] = PersonRef(
                    id: replacement.id,
                    name: replacement.name
                )
            }
        }

        let clone = TemplateCloner.clone(
            source.draft,
            options: .init(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                keepAssignees: keepAssignees,
                personRemap: remap
            )
        )

        let document = DocumentMaterializer.makeDocument(
            from: clone,
            in: context,
            isTemplate: pinAsTemplate,
            templateSourceID: source.id
        )
        // A copy keeps the template's own people order. Anyone swapped in is not in it and
        // falls back to the global order.
        if keepAssignees {
            document.peopleOrderRaw = source.peopleOrderRaw
        }

        dismiss()
        onCreated(document)
    }
}
