//
//  DocumentTableTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class DocumentTableTests: XCTestCase {

    func testHeaderIsRuledAndColumnsAreAligned() {
        let out = DocumentTable.render(
            columns: ["Name", "Size"],
            rows: [["a.jpg", "5.1 MB"], ["much-longer-name.jpg", "12 MB"]]
        )
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(lines[0], "Name                  Size")
        XCTAssertEqual(lines[1], "--------------------  ------")
        XCTAssertEqual(lines[2], "a.jpg                 5.1 MB")
        XCTAssertEqual(lines[3], "much-longer-name.jpg  12 MB")
    }

    /// Numbers line up on their last digit or they cannot be compared down a
    /// column.
    func testNumericColumnsCanSitFlushRight() {
        let out = DocumentTable.render(
            columns: ["File", "Bytes"],
            rows: [["a", "5"], ["b", "1200"]],
            alignments: [1: .trailing]
        )
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[2], "a         5")
        XCTAssertEqual(lines[3], "b      1200")
    }

    /// The whole point of this renderer rather than ``TextTable``: a document
    /// has no terminal to be narrower than.
    func testNothingIsEverTruncated() {
        let long = String(repeating: "x", count: 400)
        let out = DocumentTable.render(columns: ["Path"], rows: [[long]])
        XCTAssertTrue(out.contains(long))
        XCTAssertFalse(out.contains("…"))
    }

    /// A newline inside a cell would break the layout of every row under it.
    func testLineBreaksInCellsBecomeSpaces() {
        let out = DocumentTable.render(
            columns: ["Comment"],
            rows: [["first\nsecond"], ["tab\there"]]
        )
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4, "two rows, a header and a rule")
        XCTAssertTrue(out.contains("first second"))
        XCTAssertTrue(out.contains("tab here"))
    }

    /// A ragged row must not shift another record's values sideways.
    func testShortAndLongRowsAreSquared() {
        let out = DocumentTable.render(
            columns: ["A", "B"],
            rows: [["only"], ["one", "two", "three"]]
        )
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[2], "only")
        XCTAssertEqual(lines[3], "one   two")
    }

    func testTrailingWhitespaceIsNotEmitted() {
        let out = DocumentTable.render(columns: ["A", "B"], rows: [["x", "y"]])
        for line in out.split(separator: "\n") {
            XCTAssertFalse(line.hasSuffix(" "), "line ends in padding: '\(line)'")
        }
    }

    /// An accented letter is one column wide, not two.
    func testWidthIsCountedInCharactersAPersonSees() {
        XCTAssertEqual(DocumentTable.width(of: "café"), 4)
        XCTAssertEqual(DocumentTable.width(of: "e\u{0301}"), 1, "a combining accent is one character")

        let out = DocumentTable.render(columns: ["Name"], rows: [["café"], ["cafe"]])
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[1], "----", "the rule matches the widest cell")
    }

    func testPredicateFormChoosesAlignment() {
        let out = DocumentTable.render(
            columns: ["File", "Bytes"],
            rows: [["a", "5"], ["b", "1200"]],
            trailing: { $0 == 1 }
        )
        XCTAssertTrue(out.contains("a         5"))
    }

    func testRuleCanBeSuppressed() {
        let out = DocumentTable.render(columns: ["A"], rows: [["x"]], rule: false)
        XCTAssertEqual(out, "A\nx\n")
    }

    func testEmptyColumnsRenderNothing() {
        XCTAssertEqual(DocumentTable.render(columns: [], rows: [["x"]]), "")
    }
}
