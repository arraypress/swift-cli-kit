//
//  TableTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class TableTests: XCTestCase {

    private func table(_ json: String) -> Table { Table(from: Data(json.utf8)) }

    // MARK: - Shape

    func testColumnsAreTheUnionAcrossRecords() {
        // A record missing an optional field must not shorten the table or shift
        // other records' values into the wrong columns.
        let t = table("""
            [{"a":1,"b":2},{"a":3,"c":4}]
            """)
        XCTAssertEqual(t.columns, ["a", "b", "c"])
        XCTAssertEqual(t.rows.count, 2)
        XCTAssertEqual(t.rows[1]["b"], "")
        XCTAssertEqual(t.rows[1]["c"], "4")
    }

    func testSingleObjectBecomesOneRow() {
        let t = table(#"{"title":"Hello","views":42}"#)
        XCTAssertEqual(t.columns, ["title", "views"])
        XCTAssertEqual(t.rows.first?["views"], "42")
    }

    func testNestedValuesAreJSONEncodedNotDropped() {
        // A truncated cell is recoverable; a missing one is not.
        let t = table(#"[{"tags":["a","b"],"meta":{"x":1}}]"#)
        XCTAssertEqual(t.rows[0]["tags"], #"["a","b"]"#)
        XCTAssertEqual(t.rows[0]["meta"], #"{"x":1}"#)
    }

    func testNullBecomesEmptyAndBoolsReadAsWords() {
        let t = table(#"[{"a":null,"b":true,"c":false}]"#)
        XCTAssertEqual(t.rows[0]["a"], "")
        XCTAssertEqual(t.rows[0]["b"], "true")
        XCTAssertEqual(t.rows[0]["c"], "false")
    }

    func testIntegersZeroAndOneAreNotRewrittenAsBooleans() {
        // Regression: JSONSerialization boxes both in NSNumber, and
        // `NSNumber(1) as? Bool` succeeds — so a count of 1 rendered as "true".
        let t = table(#"[{"count":1,"other":0,"many":6}]"#)
        XCTAssertEqual(t.rows[0]["count"], "1")
        XCTAssertEqual(t.rows[0]["other"], "0")
        XCTAssertEqual(t.rows[0]["many"], "6")
    }

    func testBooleansAndUnitIntegersCoexistInOneRow() {
        let t = table(#"[{"flag":true,"count":1}]"#)
        XCTAssertEqual(t.rows[0]["flag"], "true")
        XCTAssertEqual(t.rows[0]["count"], "1")
    }

    func testFloatsKeepTheirFraction() {
        XCTAssertEqual(table(#"[{"d":211.32}]"#).rows[0]["d"], "211.32")
    }

    // MARK: - CSV

    func testCSVHasHeaderAndCRLFPerRFC4180() {
        let out = table(#"[{"a":"1"},{"a":"2"}]"#).render(as: .csv)
        XCTAssertEqual(out, "a\r\n1\r\n2\r\n")
    }

    func testCSVQuotesFieldsContainingDelimiters() {
        let out = table(#"[{"a":"x,y"},{"a":"say \"hi\""},{"a":"line\nbreak"}]"#).render(as: .csv)
        XCTAssertTrue(out.contains("\"x,y\""), out)
        XCTAssertTrue(out.contains("\"say \"\"hi\"\"\""), out)
        XCTAssertTrue(out.contains("\"line\nbreak\""), out)
    }

    func testCSVLeavesPlainFieldsUnquoted() {
        XCTAssertTrue(table(#"[{"a":"plain"}]"#).render(as: .csv).contains("\r\nplain\r\n"))
    }

    func testCSVRoundTripsThroughAParser() throws {
        // Parse the output back with a minimal RFC 4180 reader to prove the
        // quoting is not merely plausible.
        let out = table(#"[{"a":"x,y","b":"say \"hi\""}]"#).render(as: .csv)
        let fields = Self.parseCSVLine(out.components(separatedBy: "\r\n")[1])
        XCTAssertEqual(fields, ["x,y", "say \"hi\""])
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = Array(line).makeIterator()
        var pending: Character? = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" { current.append("\""); pending = iterator.next() }
                    else { inQuotes = false }
                } else { current.append(character) }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current); current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    // MARK: - Markdown

    func testMarkdownHasHeaderAndSeparator() {
        let out = table(#"[{"a":"1","b":"2"}]"#).render(as: .markdown)
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "| a | b |")
        XCTAssertEqual(lines[1], "| --- | --- |")
        XCTAssertEqual(lines[2], "| 1 | 2 |")
    }

    func testMarkdownEscapesPipesSoRowsCannotBreak() {
        let out = table(#"[{"a":"x|y"}]"#).render(as: .markdown)
        XCTAssertTrue(out.contains(#"x\|y"#), out)
    }

    func testMarkdownFlattensNewlinesToLineBreaks() {
        // A raw newline in a cell would terminate the table row.
        let out = table(#"[{"a":"one\ntwo"}]"#).render(as: .markdown)
        XCTAssertTrue(out.contains("one<br>two"), out)
        XCTAssertEqual(out.split(separator: "\n").count, 3)
    }

    // MARK: - Edge Cases

    func testEmptyInputRendersNothing() {
        XCTAssertEqual(table("[]").render(as: .csv), "")
        XCTAssertEqual(table("[]").render(as: .markdown), "")
    }

    func testNonTabularFormatRendersNothing() {
        XCTAssertEqual(table(#"[{"a":1}]"#).render(as: .json), "")
    }

    // MARK: - Rendering rows directly

    func testRenderColumnsAndRowsToCSV() {
        let csv = Table.render(
            columns: ["START", "TEXT"],
            rows: [["0:01", "hello"], ["0:04", "say \"hi\", then go"]],
            as: .csv
        )
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "START,TEXT")
        XCTAssertEqual(lines[2], "0:04,\"say \"\"hi\"\", then go\"")
    }

    func testRaggedRowsAreSquaredOff() {
        // A short row must pad, not shift the next value into the wrong column.
        let csv = Table.render(columns: ["A", "B", "C"], rows: [["1"], ["1", "2", "3", "4"]], as: .csv)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[1], "1,,")
        XCTAssertEqual(lines[2], "1,2,3")
    }

    func testRenderToMarkdown() {
        let md = Table.render(columns: ["A", "B"], rows: [["1", "2"]], as: .markdown)
        XCTAssertTrue(md.contains("| A | B |"))
        XCTAssertTrue(md.contains("| 1 | 2 |"))
    }
}
