//
//  TextTableTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class TextTableTests: XCTestCase {

    private func lines(_ rendered: String) -> [String] {
        rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    // MARK: - Layout

    func testColumnsAlignAcrossRows() {
        let out = lines(TextTable.render(
            columns: ["ID", "TITLE"],
            rows: [["a", "short"], ["bbbbb", "longer title"]],
            width: 80
        ))

        // Header, rule, two rows.
        XCTAssertEqual(out.count, 4)

        // The second column's content must begin at the same offset on every
        // line — located by its known text, not by scanning for whitespace,
        // which lands inside the first column's padding.
        let offsets = [(out[0], "TITLE"), (out[2], "short"), (out[3], "longer title")].map { line, content in
            line.distance(from: line.startIndex, to: line.range(of: content)!.lowerBound)
        }
        XCTAssertEqual(Set(offsets).count, 1, "second column misaligned: \(out)")
    }

    func testHeaderRuleMatchesColumnWidths() {
        let out = lines(TextTable.render(columns: ["AB", "CDEF"], rows: [["x", "y"]], width: 80))
        XCTAssertEqual(out[1], "──  ────")
    }

    func testNoTrailingWhitespaceOnAnyLine() {
        // Lines get copied out of terminals; invisible padding travels with them.
        let out = lines(TextTable.render(
            columns: ["A", "LONGHEADER"],
            rows: [["x", "y"]],
            width: 80
        ))
        for line in out {
            XCTAssertEqual(line, String(line.reversed().drop { $0 == " " }.reversed()), "trailing space in \(line.debugDescription)")
        }
    }

    func testEmptyInputRendersNothing() {
        XCTAssertEqual(TextTable.render(columns: [], rows: [], width: 80), "")
    }

    func testShortRowIsPaddedNotDropped() {
        let out = lines(TextTable.render(columns: ["A", "B", "C"], rows: [["x"]], width: 80))
        XCTAssertEqual(out.count, 3)
        XCTAssertTrue(out[2].hasPrefix("x"))
    }

    // MARK: - Fitting

    func testOverWideTableIsTruncatedToTheTerminal() {
        let out = lines(TextTable.render(
            columns: ["ID", "TITLE"],
            rows: [["abc", String(repeating: "x", count: 200)]],
            width: 40
        ))
        for line in out {
            XCTAssertLessThanOrEqual(TextTable.displayWidth(line), 40, line)
        }
        XCTAssertTrue(out[2].contains("…"))
    }

    func testOnlyFlexibleColumnsAreShortened() {
        // A truncated identifier is one the reader cannot copy or reuse, which is
        // worse than a truncated title.
        let identifier = "PXC_PYeB6F8"
        let out = lines(TextTable.render(
            columns: ["ID", "TITLE"],
            rows: [[identifier, String(repeating: "x", count: 200)]],
            flexible: [1],
            width: 40
        ))
        XCTAssertTrue(out[2].hasPrefix(identifier), "identifier was truncated: \(out[2])")
    }

    func testTruncationAddsAnEllipsisWithinBudget() {
        XCTAssertEqual(TextTable.truncate("abcdefghij", to: 5), "abcd…")
        XCTAssertEqual(TextTable.truncate("abc", to: 5), "abc")
    }

    // MARK: - Width

    func testEmojiAndCJKCountAsTwoColumns() {
        // Counting characters instead of cells misaligns every subsequent row —
        // a very common way terminal tables break.
        XCTAssertEqual(TextTable.displayWidth("ab"), 2)
        XCTAssertEqual(TextTable.displayWidth("🧚"), 2)
        XCTAssertEqual(TextTable.displayWidth("日本"), 4)
    }

    func testRowsWithEmojiStayAligned() {
        let out = lines(TextTable.render(
            columns: ["NAME", "X"],
            rows: [["plain", "1"], ["🧚 fae", "2"]],
            width: 80
        ))
        let widths = [out[2], out[3]].map { line -> Int in
            TextTable.displayWidth(String(line.prefix(while: { $0 != "1" && $0 != "2" })))
        }
        XCTAssertEqual(Set(widths).count, 1, "emoji row misaligned: \(out)")
    }

    // MARK: - Cell Safety

    func testNewlinesAreFoldedSoRowsCannotBreak() {
        let out = lines(TextTable.render(
            columns: ["A"],
            rows: [["one\ntwo\r\nthree"]],
            width: 80
        ))
        XCTAssertEqual(out.count, 3, "a cell newline split the row")
        XCTAssertTrue(out[2].contains("one two three"))
    }

    func testTabsAreFoldedToo() {
        let out = lines(TextTable.render(columns: ["A"], rows: [["a\tb"]], width: 80))
        XCTAssertFalse(out[2].contains("\t"))
    }
}
