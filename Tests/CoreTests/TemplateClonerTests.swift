import XCTest
@testable import TallyCore

final class TemplateClonerTests: XCTestCase {

    private let alma = PersonRef(id: UUID(), name: "Alma")
    private let vidar = PersonRef(id: UUID(), name: "Vidar")

    private func partlyPackedList() -> DocumentDraft {
        DocumentDraft(
            title: "Packing list",
            blocks: [
                BlockDraft(kind: .heading2, text: "Clothes"),
                BlockDraft(
                    kind: .todo,
                    text: "2 pairs of socks",
                    assignments: [
                        AssignmentDraft(person: alma, isDone: true),
                        AssignmentDraft(person: vidar, isDone: false),
                    ]
                ),
                BlockDraft(kind: .todo, text: "Charger", isDoneSolo: true),
            ]
        )
    }

    func testCloneKeepsStructureAndClearsProgress() {
        let source = partlyPackedList()
        let clone = TemplateCloner.clone(source, options: .init(title: "Trip to Åre"))

        XCTAssertEqual(clone.title, "Trip to Åre")
        XCTAssertEqual(clone.blocks.map(\.kind), source.blocks.map(\.kind))
        XCTAssertEqual(clone.blocks.map(\.text), source.blocks.map(\.text))
        XCTAssertEqual(clone.completedTodoCount, 0)
        XCTAssertTrue(clone.blocks.allSatisfy { !$0.isDoneSolo })
        XCTAssertTrue(clone.blocks.allSatisfy { block in
            block.assignments.allSatisfy { assignment in !assignment.isDone }
        })
    }

    func testCloneKeepsAssigneesByDefault() {
        let clone = TemplateCloner.clone(partlyPackedList(), options: .init(title: "Next trip"))
        XCTAssertEqual(clone.blocks[1].people.map(\.name), ["Alma", "Vidar"])
    }

    func testCloneCanDropAssignees() {
        let clone = TemplateCloner.clone(
            partlyPackedList(),
            options: .init(title: "Next trip", keepAssignees: false)
        )
        XCTAssertTrue(clone.blocks.allSatisfy(\.assignments.isEmpty))
    }

    func testCloneGivesEverythingFreshIdentifiers() {
        let source = partlyPackedList()
        let clone = TemplateCloner.clone(source, options: .init(title: "Next trip"))

        XCTAssertNotEqual(clone.id, source.id)
        XCTAssertTrue(Set(clone.blocks.map(\.id)).isDisjoint(with: Set(source.blocks.map(\.id))))
    }

    func testRemapSwapsOnePersonForAnother() {
        let nils = PersonRef(id: UUID(), name: "Nils")
        let clone = TemplateCloner.clone(
            partlyPackedList(),
            options: .init(title: "Next trip", personRemap: ["vidar": nils])
        )
        XCTAssertEqual(clone.blocks[1].people.map(\.name), ["Alma", "Nils"])
    }

    func testRemapOntoTheSamePersonDoesNotDuplicateThem() {
        let clone = TemplateCloner.clone(
            partlyPackedList(),
            options: .init(title: "Next trip", personRemap: ["vidar": alma])
        )
        XCTAssertEqual(clone.blocks[1].people.map(\.name), ["Alma"])
    }

    func testResetClearsBoxesButKeepsIdentifiers() {
        let source = partlyPackedList()
        let reset = TemplateCloner.reset(source)

        XCTAssertEqual(reset.id, source.id)
        XCTAssertEqual(reset.blocks.map(\.id), source.blocks.map(\.id))
        XCTAssertEqual(reset.completedTodoCount, 0)
        XCTAssertEqual(reset.blocks[1].people.map(\.name), ["Alma", "Vidar"])
    }

    func testSuggestedTitleBuildsOnTheSourceName() {
        let date = Date(timeIntervalSince1970: 1_722_000_000)
        let title = TemplateCloner.suggestedTitle(
            basedOn: partlyPackedList(),
            date: date,
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_GB")
        )
        XCTAssertTrue(title.hasPrefix("Packing list — "), "unexpected title: \(title)")
    }
}
