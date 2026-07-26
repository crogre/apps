import SwiftUI

/// A person's initials in their own colour. Used everywhere a person appears.
struct PersonAvatar: View {
    let person: Person
    var size: CGFloat = 22
    /// Dimmed once this person has ticked their own box.
    var isDone: Bool = false

    var body: some View {
        Text(verbatim: person.initials)
            .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(person.color.opacity(isDone ? 0.35 : 1), in: Circle())
            .overlay {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(person.color)
                }
            }
            .accessibilityLabel(person.name)
            .accessibilityValue(isDone ? "done" : "not done")
    }
}

/// Avatar plus name, for the assignee row under a todo.
struct PersonChip: View {
    let person: Person
    var isDone: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            PersonAvatar(person: person, size: 18, isDone: isDone)
            Text(verbatim: person.name)
                .font(.caption)
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? .secondary : .primary)
        }
        .padding(.leading, 2)
        .padding(.trailing, 7)
        .padding(.vertical, 2)
        .background(person.color.opacity(isDone ? 0.06 : 0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// The overlapping avatar stack shown on a document row.
struct PersonAvatarStack: View {
    let people: [Person]
    var size: CGFloat = 20
    var maxVisible: Int = 4

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(people.prefix(maxVisible), id: \.id) { person in
                PersonAvatar(person: person, size: size)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
            if people.count > maxVisible {
                Text(verbatim: "+\(people.count - maxVisible)")
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Color(.secondarySystemFill), in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(people.map(\.name).formatted(.list(type: .and)))
    }
}
