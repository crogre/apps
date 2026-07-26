import XCTest
@testable import TallyCore

final class CompletionRollupTests: XCTestCase {

    func testUnassignedItemFallsBackToTheSharedFlag() {
        let open = CompletionRollup(doneCount: 0, totalCount: 0, isDoneSolo: false)
        XCTAssertTrue(open.isUnassigned)
        XCTAssertFalse(open.isComplete)
        XCTAssertFalse(open.needsCompleterPrompt)
        XCTAssertNil(open.progressText)

        let done = CompletionRollup(doneCount: 0, totalCount: 0, isDoneSolo: true)
        XCTAssertTrue(done.isComplete)
    }

    func testSingleAssigneeTicksDirectly() {
        let rollup = CompletionRollup(doneCount: 0, totalCount: 1, isDoneSolo: false)
        XCTAssertFalse(rollup.needsCompleterPrompt, "one assignee is unambiguous, no popup")
        XCTAssertNil(rollup.progressText)
        XCTAssertFalse(rollup.isComplete)
    }

    func testTwoAssigneesNeedTheCompleterPrompt() {
        let rollup = CompletionRollup(doneCount: 0, totalCount: 2, isDoneSolo: false)
        XCTAssertTrue(rollup.needsCompleterPrompt)
        XCTAssertEqual(rollup.progressText, "0/2")
    }

    func testHalfDoneIsPartialNotComplete() {
        let rollup = CompletionRollup(doneCount: 1, totalCount: 2, isDoneSolo: false)
        XCTAssertTrue(rollup.isPartial)
        XCTAssertFalse(rollup.isComplete)
        XCTAssertEqual(rollup.progressText, "1/2")
        XCTAssertEqual(rollup.symbolName, "circle.lefthalf.filled")
        XCTAssertEqual(rollup.fractionComplete, 0.5)
    }

    func testCompleteOnlyWhenEveryoneIsDone() {
        let rollup = CompletionRollup(doneCount: 2, totalCount: 2, isDoneSolo: false)
        XCTAssertTrue(rollup.isComplete)
        XCTAssertFalse(rollup.isPartial)
        XCTAssertEqual(rollup.symbolName, "checkmark.circle.fill")
    }

    func testSoloFlagIsIgnoredOnceSomebodyIsAssigned() {
        // The stale flag from a previously unassigned item must not complete it.
        let rollup = CompletionRollup(doneCount: 0, totalCount: 2, isDoneSolo: true)
        XCTAssertFalse(rollup.isComplete)
    }

    func testEmptySymbolForUntouchedItem() {
        XCTAssertEqual(
            CompletionRollup(doneCount: 0, totalCount: 2, isDoneSolo: false).symbolName,
            "circle"
        )
    }

    func testDocumentCountsRollUpAcrossBlocks() {
        let document = DocumentDraft(
            title: "List",
            blocks: [
                BlockDraft(kind: .heading1, text: "Not a todo"),
                BlockDraft(kind: .todo, text: "Done", isDoneSolo: true),
                BlockDraft(
                    kind: .todo,
                    text: "Half",
                    assignments: [
                        AssignmentDraft(person: PersonRef(name: "A"), isDone: true),
                        AssignmentDraft(person: PersonRef(name: "B"), isDone: false),
                    ]
                ),
            ]
        )
        XCTAssertEqual(document.todoCount, 2)
        XCTAssertEqual(document.completedTodoCount, 1)
    }

    func testDistinctPeopleAreListedInFirstAppearanceOrder() {
        let document = DocumentDraft(
            title: "List",
            blocks: [
                BlockDraft(kind: .todo, text: "One", assignments: [
                    AssignmentDraft(person: PersonRef(name: "Vidar")),
                    AssignmentDraft(person: PersonRef(name: "Alma")),
                ]),
                BlockDraft(kind: .todo, text: "Two", assignments: [
                    AssignmentDraft(person: PersonRef(name: "alma")),
                    AssignmentDraft(person: PersonRef(name: "Nils")),
                ]),
            ]
        )
        XCTAssertEqual(document.distinctPeople.map(\.name), ["Vidar", "Alma", "Nils"])
    }
}
