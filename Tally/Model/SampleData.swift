import Foundation
import SwiftData

/// Preview and first-launch data.
///
/// The packing list is the use case the app was built around, so it doubles as the sample
/// document: two kids, identical items, one shared line each.
enum SampleData {

    static let packingListMarkdown = """
    # Packing list

    Two nights, so one change of clothes each plus what they are wearing.

    ## Clothes
    - [ ] 2 pairs of socks
    - [ ] 2 pairs of underwear
    - [ ] Warm jumper
    - [ ] Rain jacket

    ## Bathroom
    - [ ] Toothbrush
    - [ ] Hairbrush

    ## Don't forget
    - [ ] Charger
    - [ ] Passport
    """

    /// Builds the sample packing list with both kids assigned to every clothing item.
    @discardableResult
    static func insertPackingList(
        into context: ModelContext,
        assignees names: [String] = ["Alma", "Vidar"]
    ) -> Document {
        let people = PersonStore(context: context)
        let assignees = names.compactMap { people.findOrCreate(named: $0) }
        // Settle the new people before anything looks them up again by name.
        try? context.save()

        var draft = MarkdownParser.document(from: packingListMarkdown)
        // Every todo under a heading goes to both kids; the "Don't forget" items are the
        // parent's job and stay unassigned.
        var currentHeading = ""
        draft.blocks = draft.blocks.map { block in
            var copy = block
            if let level = block.kind.headingLevel, level >= 2 {
                currentHeading = block.text
            }
            if block.kind == .todo, currentHeading == "Clothes" || currentHeading == "Bathroom" {
                copy.assignments = assignees.map {
                    AssignmentDraft(person: PersonRef(id: $0.id, name: $0.name))
                }
            }
            return copy
        }

        let document = DocumentMaterializer.makeDocument(from: draft, in: context)
        document.isTemplate = true
        return document
    }

    /// Seeds the store the first time the app runs, so it does not open on a blank screen.
    static func seedIfEmpty(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Document>())) ?? 0
        guard existing == 0 else { return }
        insertPackingList(into: context)
        try? context.save()
    }

    /// In-memory container for SwiftUI previews.
    @MainActor
    static func previewContainer() -> ModelContainer {
        let container = ModelContainer.tally(inMemory: true)
        insertPackingList(into: container.mainContext)
        return container
    }
}
