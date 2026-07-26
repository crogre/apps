import XCTest
@testable import TallyCore

final class FractionalIndexTests: XCTestCase {

    func testInsertingBetweenTwoBlocksSortsBetweenThem() {
        let middle = FractionalIndex.between(1, 2)
        XCTAssertGreaterThan(middle, 1)
        XCTAssertLessThan(middle, 2)
    }

    func testInsertingAtTheTopAndBottom() {
        XCTAssertLessThan(FractionalIndex.between(nil, 0), 0)
        XCTAssertGreaterThan(FractionalIndex.between(0, nil), 0)
        XCTAssertEqual(FractionalIndex.between(nil, nil), 0)
    }

    func testAppendingToAnEmptyDocument() {
        XCTAssertEqual(FractionalIndex.append(after: []), 0)
        XCTAssertEqual(FractionalIndex.append(after: [0, 1, 2]), 3)
    }

    func testRepeatedSplittingStaysOrdered() {
        var positions = [0.0, 1.0]
        for _ in 0..<20 {
            let inserted = FractionalIndex.between(positions[0], positions[1])
            positions = [positions[0], inserted]
        }
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertGreaterThan(positions[1], positions[0])
    }

    func testRenormalisationIsFlaggedOnlyWhenRoomRunsOut() {
        XCTAssertFalse(FractionalIndex.needsRenormalisation([0, 1, 2]))
        XCTAssertFalse(FractionalIndex.needsRenormalisation([]))
        XCTAssertFalse(FractionalIndex.needsRenormalisation([5]))
        XCTAssertTrue(FractionalIndex.needsRenormalisation([0, 1e-12, 1]))
        XCTAssertTrue(FractionalIndex.needsRenormalisation([1, 1]), "duplicates must be fixed")
    }

    func testRenormalisedPositionsAreEvenlySpaced() {
        XCTAssertEqual(FractionalIndex.renormalised(count: 4), [0, 1, 2, 3])
        XCTAssertEqual(FractionalIndex.renormalised(count: 0), [])
    }
}

final class TypingShortcutTests: XCTestCase {

    func testHeadingShortcuts() {
        XCTAssertEqual(
            TypingShortcut.match(text: "# Title", currentKind: .paragraph),
            TypingShortcut.Match(kind: .heading1, remainingText: "Title")
        )
        XCTAssertEqual(
            TypingShortcut.match(text: "### Deep", currentKind: .paragraph),
            TypingShortcut.Match(kind: .heading3, remainingText: "Deep")
        )
    }

    func testTodoShortcutsAcceptBothSpellings() {
        for prefix in ["[] ", "[ ] ", "- [] ", "- [ ] "] {
            XCTAssertEqual(
                TypingShortcut.match(text: prefix + "Socks", currentKind: .paragraph),
                TypingShortcut.Match(kind: .todo, remainingText: "Socks"),
                "failed for prefix \(prefix)"
            )
        }
    }

    func testBulletShortcut() {
        XCTAssertEqual(
            TypingShortcut.match(text: "- Item", currentKind: .paragraph),
            TypingShortcut.Match(kind: .bullet, remainingText: "Item")
        )
    }

    func testBulletCanBecomeATodo() {
        XCTAssertEqual(
            TypingShortcut.match(text: "[] Socks", currentKind: .bullet),
            TypingShortcut.Match(kind: .todo, remainingText: "Socks")
        )
    }

    func testBulletDoesNotRetriggerAsABullet() {
        XCTAssertNil(TypingShortcut.match(text: "- Item", currentKind: .bullet))
    }

    func testDividerShortcut() {
        XCTAssertEqual(
            TypingShortcut.match(text: "---", currentKind: .paragraph),
            TypingShortcut.Match(kind: .divider, remainingText: "")
        )
    }

    func testNoShortcutInsideAHeadingOrTodo() {
        XCTAssertNil(TypingShortcut.match(text: "# not again", currentKind: .heading1))
        XCTAssertNil(TypingShortcut.match(text: "- [ ] nested", currentKind: .todo))
    }

    func testPlainTextIsLeftAlone() {
        XCTAssertNil(TypingShortcut.match(text: "Just writing", currentKind: .paragraph))
        XCTAssertNil(TypingShortcut.match(text: "#NoSpace", currentKind: .paragraph))
    }
}
