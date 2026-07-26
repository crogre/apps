import XCTest
@testable import TallyCore

final class MarkdownTests: XCTestCase {

    // The document from the README, and the reason the app exists.
    private func packingList() -> DocumentDraft {
        DocumentDraft(
            title: "Trip to Åre",
            blocks: [
                BlockDraft(kind: .heading2, text: "Kids"),
                BlockDraft(
                    kind: .todo,
                    text: "2 pairs of socks",
                    assignments: [
                        AssignmentDraft(person: PersonRef(name: "Alma"), isDone: true),
                        AssignmentDraft(person: PersonRef(name: "Vidar"), isDone: false),
                    ]
                ),
                BlockDraft(
                    kind: .todo,
                    text: "Toothbrush",
                    assignments: [AssignmentDraft(person: PersonRef(name: "Alma"), isDone: true)]
                ),
                BlockDraft(kind: .todo, text: "Sunscreen"),
            ]
        )
    }

    func testSerializesToTheDocumentedFormat() {
        let expected = """
        # Trip to Åre

        ## Kids

        - [ ] 2 pairs of socks @Alma✓ @Vidar
        - [x] Toothbrush @Alma
        - [ ] Sunscreen
        """
        XCTAssertEqual(MarkdownSerializer.markdown(for: packingList()), expected)
    }

    func testPartiallyDoneItemKeepsAnUncheckedBox() {
        let block = BlockDraft(
            kind: .todo,
            text: "Socks",
            assignments: [
                AssignmentDraft(person: PersonRef(name: "Alma"), isDone: true),
                AssignmentDraft(person: PersonRef(name: "Vidar"), isDone: false),
            ]
        )
        XCTAssertEqual(MarkdownSerializer.line(for: block), "- [ ] Socks @Alma✓ @Vidar")
    }

    func testCheckedBoxOnlyOnceEveryoneIsDone() {
        var block = BlockDraft(
            kind: .todo,
            text: "Socks",
            assignments: [
                AssignmentDraft(person: PersonRef(name: "Alma"), isDone: true),
                AssignmentDraft(person: PersonRef(name: "Vidar"), isDone: true),
            ]
        )
        XCTAssertEqual(MarkdownSerializer.line(for: block), "- [x] Socks @Alma✓ @Vidar✓")

        block.assignments[1].isDone = false
        XCTAssertEqual(MarkdownSerializer.line(for: block), "- [ ] Socks @Alma✓ @Vidar")
    }

    func testRoundTripPreservesContent() {
        let original = packingList()
        let parsed = MarkdownParser.document(from: MarkdownSerializer.markdown(for: original))
        XCTAssertTrue(original.contentEquals(parsed), "round trip changed the document:\n\(parsed)")
    }

    func testRoundTripPreservesEveryBlockKindAndIndent() {
        let original = DocumentDraft(
            title: "Everything",
            blocks: [
                BlockDraft(kind: .heading1, text: "One"),
                BlockDraft(kind: .paragraph, text: "Some **bold** prose."),
                BlockDraft(kind: .heading2, text: "Two"),
                BlockDraft(kind: .heading3, text: "Three"),
                BlockDraft(kind: .bullet, text: "Top"),
                BlockDraft(kind: .bullet, text: "Nested", indent: 1),
                BlockDraft(kind: .divider),
                BlockDraft(kind: .todo, text: "Deep todo", indent: 2, isDoneSolo: true),
            ]
        )
        let parsed = MarkdownParser.document(from: MarkdownSerializer.markdown(for: original))
        XCTAssertTrue(original.contentEquals(parsed))
    }

    func testLeadingHeadingBecomesTheTitle() {
        let parsed = MarkdownParser.document(from: "# Groceries\n\n- [ ] Milk")
        XCTAssertEqual(parsed.title, "Groceries")
        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks.first?.kind, .todo)
    }

    func testHeadingFurtherDownStaysABlock() {
        let parsed = MarkdownParser.document(from: "Intro line\n\n# Not the title")
        XCTAssertEqual(parsed.title, "")
        XCTAssertEqual(parsed.blocks.map(\.kind), [.paragraph, .heading1])
    }

    // MARK: - Mentions

    func testNameWithSpacesUsesBrackets() {
        let block = BlockDraft(
            kind: .todo,
            text: "Passport",
            assignments: [AssignmentDraft(person: PersonRef(name: "Alma Svensson"), isDone: true)]
        )
        XCTAssertEqual(MarkdownSerializer.line(for: block), "- [x] Passport @[Alma Svensson]✓")

        let parsed = MarkdownParser.block(from: MarkdownSerializer.line(for: block))
        XCTAssertEqual(parsed.text, "Passport")
        XCTAssertEqual(parsed.assignments.map(\.person.name), ["Alma Svensson"])
        XCTAssertEqual(parsed.assignments.map(\.isDone), [true])
    }

    func testEmailAddressIsNotAMention() {
        let parsed = MarkdownParser.block(from: "- [ ] Mail teacher@school.se")
        XCTAssertEqual(parsed.text, "Mail teacher@school.se")
        XCTAssertTrue(parsed.assignments.isEmpty)
    }

    func testMentionsOnlyCountAtTheEndOfTheLine() {
        let parsed = MarkdownParser.block(from: "- [ ] Ask @Alma about the tickets")
        XCTAssertEqual(parsed.text, "Ask @Alma about the tickets")
        XCTAssertTrue(parsed.assignments.isEmpty)
    }

    func testTrailingMentionsAreStrippedInOrder() {
        let parsed = MarkdownParser.block(from: "- [ ] Socks @Alma✓ @Vidar @[Nils Berg]")
        XCTAssertEqual(parsed.text, "Socks")
        XCTAssertEqual(parsed.assignments.map(\.person.name), ["Alma", "Vidar", "Nils Berg"])
        XCTAssertEqual(parsed.assignments.map(\.isDone), [true, false, false])
    }

    func testCheckedBoxWithNoAssigneesSetsSoloCompletion() {
        let parsed = MarkdownParser.block(from: "- [x] Sunscreen")
        XCTAssertTrue(parsed.isDoneSolo)
        XCTAssertTrue(parsed.completion.isComplete)
    }

    func testPerPersonMarksWinOverTheBox() {
        // A hand-written file can disagree with itself; the per-person marks are the detail
        // and so are treated as authoritative.
        let parsed = MarkdownParser.block(from: "- [x] Socks @Alma✓ @Vidar")
        XCTAssertFalse(parsed.completion.isComplete)
        XCTAssertEqual(parsed.completion.progressText, "1/2")
    }

    func testConsecutiveProseLinesMergeIntoOneParagraph() {
        let parsed = MarkdownParser.document(from: "Hello there\nsecond line\n\nNew paragraph")
        XCTAssertEqual(parsed.blocks.map(\.text), ["Hello there second line", "New paragraph"])
    }

    func testParsesForeignMarkdownWithStarBullets() {
        let parsed = MarkdownParser.document(from: "* plain bullet\n* [x] done thing")
        XCTAssertEqual(parsed.blocks.map(\.kind), [.bullet, .todo])
        XCTAssertTrue(parsed.blocks[1].isDoneSolo)
    }
}
