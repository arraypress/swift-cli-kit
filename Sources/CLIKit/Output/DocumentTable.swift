//
//  DocumentTable.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A plain-text table meant for a file, not for a terminal.
//
//  ``TextTable`` renders for the window it is printed into: it measures the
//  terminal and shortens flexible columns to fit. That is right for a person
//  reading a result and wrong for a document — a listing saved beside the files
//  it describes, or printed, or mailed, has no terminal and must not lose a
//  character to one. So this pads to the widest cell, rules off the header and
//  never truncates anything.
//

import Foundation

/// Lays rows out in fixed-width columns for a text document.
public enum DocumentTable {

    /// How a column's cells sit in their width.
    public enum Alignment: Sendable {
        case leading
        case trailing
    }

    /// Two spaces between columns, which reads as a gap without looking like
    /// an indent.
    public static let defaultGap = "  "

    /// Renders a header, a rule and the rows, padded to the widest cell.
    ///
    /// - Parameters:
    ///   - columns: Header labels.
    ///   - rows: Cells, positionally matching `columns`. Short rows are padded
    ///     and long ones truncated, so a ragged row cannot shift another
    ///     record's values into the wrong column.
    ///   - alignments: Column indices that should sit flush right. Numbers line
    ///     up on their last digit or they cannot be compared down a column.
    ///   - gap: What separates the columns.
    ///   - rule: Whether to draw the dashed rule under the header.
    public static func render(
        columns: [String],
        rows: [[String]],
        alignments: [Int: Alignment] = [:],
        gap: String = defaultGap,
        rule: Bool = true
    ) -> String {
        guard !columns.isEmpty else { return "" }

        let squared = rows.map { row in
            columns.indices.map { $0 < row.count ? sanitise(row[$0]) : "" }
        }
        let widths = columns.indices.map { index in
            max(
                width(of: columns[index]),
                squared.map { width(of: $0[index]) }.max() ?? 0
            )
        }

        func line(_ cells: [String]) -> String {
            let padded = cells.indices.map { index -> String in
                pad(cells[index], to: widths[index], alignment: alignments[index] ?? .leading)
            }
            // Trailing padding on the last column is invisible and makes every
            // line the same length in a diff for no reason.
            return padded.joined(separator: gap).replacing(/[ ]+$/, with: "")
        }

        var out = line(columns) + "\n"
        if rule {
            out += widths.map { String(repeating: "-", count: $0) }.joined(separator: gap) + "\n"
        }
        for row in squared {
            out += line(row) + "\n"
        }
        return out
    }

    /// Renders with alignment decided per column by a predicate.
    ///
    /// Saves a caller building an index dictionary when what it actually knows
    /// is which columns hold numbers.
    public static func render(
        columns: [String],
        rows: [[String]],
        trailing: (Int) -> Bool,
        gap: String = defaultGap,
        rule: Bool = true
    ) -> String {
        var alignments: [Int: Alignment] = [:]
        for index in columns.indices where trailing(index) {
            alignments[index] = .trailing
        }
        return render(columns: columns, rows: rows, alignments: alignments, gap: gap, rule: rule)
    }

    // MARK: - Cells

    /// A line break inside a cell would break the column layout for every row
    /// beneath it, so it becomes a space.
    static func sanitise(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    /// Cell width in characters a reader sees.
    ///
    /// Counted in grapheme clusters, so an accented letter or an emoji with a
    /// skin-tone modifier is one column wide rather than two or four. It is
    /// still not the whole story — a CJK ideograph occupies two cells in a
    /// monospaced font and counts as one here — but it is right for the Latin
    /// text these listings are overwhelmingly made of, and it never splits a
    /// character.
    static func width(of value: String) -> Int {
        value.count
    }

    /// Pads a cell to a width.
    static func pad(_ value: String, to width: Int, alignment: Alignment) -> String {
        let short = width - self.width(of: value)
        guard short > 0 else { return value }
        let padding = String(repeating: " ", count: short)
        return alignment == .trailing ? padding + value : value + padding
    }
}
