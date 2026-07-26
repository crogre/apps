import SwiftUI

struct DocumentRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if document.isTemplate {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Template")
                }
                Text(verbatim: document.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
            }

            if !document.preview.isEmpty {
                Text(InlineMarkdown.attributed(document.preview))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(document.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let progress = document.progressSummary {
                    Text(verbatim: progress)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(.secondarySystemFill), in: Capsule())
                }

                Spacer(minLength: 0)

                let people = document.distinctPeople
                if !people.isEmpty {
                    PersonAvatarStack(people: people, size: 20)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
