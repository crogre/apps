import SwiftUI

/// Name and colour for one person. Changes apply as you make them, so the preview and every
/// chip and checkbox in the app follow along.
struct PersonEditorView: View {
    @Bindable var person: Person

    @State private var name = ""

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 14)]

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        PersonAvatar(person: person, size: 64)
                        PersonChip(person: person)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Name") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitName)
            }

            Section("Colour") {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(PersonPalette.colors.indices, id: \.self) { index in
                        swatch(index: index)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("Custom colour", selection: customColor, supportsOpacity: false)
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = person.name }
        .onDisappear(perform: commitName)
    }

    private func swatch(index: Int) -> some View {
        let isSelected = person.customColorHex == nil && person.colorSeed == index
        return Button {
            person.customColorHex = nil
            person.colorSeed = index
        } label: {
            Circle()
                .fill(PersonPalette.colors[index])
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? PersonPalette.colors[index] : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour \(index + 1)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Picking a custom colour replaces the palette choice; the picker opens on the
    /// person's current colour either way.
    private var customColor: Binding<Color> {
        Binding(
            get: { person.color },
            set: { person.customColorHex = PersonPalette.hex(for: $0) }
        )
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            name = person.name
        } else if trimmed != person.name {
            person.name = trimmed
        }
    }
}
