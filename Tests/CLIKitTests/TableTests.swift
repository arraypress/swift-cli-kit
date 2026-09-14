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
    // MARK: - TSV

    func testTSVIsTabSeparatedWithAHeader() {
        let out = table("""
        [{"name": "a.jpg", "size": "5 MB"}, {"name": "b.jpg", "size": "12 MB"}]
        """).render(as: .tsv)

        XCTAssertEqual(out, "name\tsize\na.jpg\t5 MB\nb.jpg\t12 MB\n")
    }

    /// TSV has no quoting convention: a spreadsheet treats every tab as a
    /// column break and every newline as a row break, full stop. A cell
    /// carrying either has to lose it, or one value silently becomes two
    /// columns and the rest of the row shifts.
    func testTSVFlattensTheCharactersThatCarryStructure() {
        let out = table("""
        [{"note": "first\\nsecond", "other": "a\\tb"}]
        """).render(as: .tsv)

        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2, "the embedded newline must not have made a third row")
        XCTAssertEqual(lines[1].split(separator: "\t").count, 2, "nor the embedded tab a third column")
        XCTAssertTrue(out.contains("first second"))
        XCTAssertTrue(out.contains("a b"))
    }

    /// The clipboard route into a spreadsheet is exactly as executable as the
    /// file route.
    func testTSVDefusesFormulaInjection() {
        let out = table("""
        [{"cell": "=SUM(A1:A9)"}]
        """).render(as: .tsv)
        XCTAssertTrue(out.contains("'=SUM(A1:A9)"))
    }

    func testNegativeNumbersAreNotDefused() {
        // A minus sign starts a formula, but it also starts every negative
        // number, and quoting those would break a numeric column on import.
        XCTAssertEqual(Table.defused("-42"), "-42")
        XCTAssertEqual(Table.defused("-42.5"), "-42.5")
        XCTAssertEqual(Table.defused("-cmd"), "'-cmd")
    }

    // MARK: - HTML

    func testHTMLIsATableFragment() {
        let out = table("""
        [{"name": "a.jpg", "size": "5 MB"}]
        """).render(as: .html)

        XCTAssertTrue(out.hasPrefix("<table>"))
        XCTAssertTrue(out.contains("<th>name</th><th>size</th>"))
        XCTAssertTrue(out.contains("<td>a.jpg</td><td>5 MB</td>"))
        XCTAssertTrue(out.contains("</table>"))
        XCTAssertFalse(out.contains("<html>"), "a fragment, so it drops into a page that has one")
    }

    /// Cells carry scraped content by design, so a value containing a tag has
    /// to arrive as text rather than as markup.
    func testHTMLEscapesEveryCell() {
        let out = table("""
        [{"payload": "<script>alert('x')</script> & \\"quoted\\""}]
        """).render(as: .html)

        XCTAssertFalse(out.contains("<script>"))
        XCTAssertTrue(out.contains("&lt;script&gt;"))
        XCTAssertTrue(out.contains("&amp;"))
        XCTAssertTrue(out.contains("&quot;"))
        XCTAssertTrue(out.contains("&#39;"))
    }

    func testHTMLEscapesHeadingsToo() {
        let out = Table.render(columns: ["<b>"], rows: [["x"]], as: .html)
        XCTAssertTrue(out.contains("<th>&lt;b&gt;</th>"))
    }

    // MARK: - Formats

    func testTabularFormatsAreMarkedAsSuch() {
        XCTAssertTrue(OutputFormat.csv.isTabular)
        XCTAssertTrue(OutputFormat.tsv.isTabular)
        XCTAssertTrue(OutputFormat.markdown.isTabular)
        XCTAssertTrue(OutputFormat.html.isTabular)
        XCTAssertFalse(OutputFormat.json.isTabular)
        XCTAssertFalse(OutputFormat.text.isTabular)
    }

    func testEveryTabularFormatRendersSomething() {
        let t = table("""
        [{"a": "1", "b": "2"}]
        """)
        for format in OutputFormat.allCases where format.isTabular {
            XCTAssertFalse(t.render(as: format).isEmpty, "\(format.rawValue) rendered nothing")
        }
    }

}
