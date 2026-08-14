//
//  Table.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Flattens encoded JSON into rows and columns for the tabular output formats.
//

import Foundation

/// A tabular view of one or more encoded records.
///
/// Built from already-encoded JSON rather than from `Encodable` directly, so it
/// works for every payload type without each one implementing a table
/// representation — and so it composes with `--fields`, which also operates on
/// the encoded form.
public struct Table {

    /// Column names, in a stable order.
    let columns: [String]

    /// One dictionary per record, keyed by column name.
    let rows: [[String: String]]

    // MARK: Initialisation

    /// Builds a table from already-keyed rows.
    private init(columns: [String], rows: [[String: String]]) {
        self.columns = columns
        self.rows = rows
    }

    /// Flattens a JSON document into rows.
    ///
    /// Accepts either a single object or an array of them. Columns are the
    /// **union** of keys across every record, sorted, so a record that happens
    /// to omit an optional field does not silently shorten the table or shift
    /// other records' values into the wrong columns.
    init(from data: Data) {
        let parsed = try? JSONSerialization.jsonObject(with: data)

        let objects: [[String: Any]]
        switch parsed {
        case let array as [Any]:
            objects = array.compactMap { $0 as? [String: Any] }
        case let object as [String: Any]:
            objects = [object]
        default:
            objects = []
        }

        var names = Set<String>()
        for object in objects { names.formUnion(object.keys) }

        // Bind locally before the closure: referring to `self.columns` inside it
        // would capture a partially initialised `self`.
        let columnNames = names.sorted()
        self.columns = columnNames

        self.rows = objects.map { object in
            var row: [String: String] = [:]
            for column in columnNames {
                row[column] = Self.cell(object[column])
            }
            return row
        }
    }

    // MARK: Cells

    /// Renders one value as a flat cell.
    ///
    /// Nested arrays and objects are JSON-encoded rather than dropped: a
    /// truncated cell is recoverable, a missing one is not.
    private static func cell(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull:
            return ""
        case let string as String:
            return string
        case let number as NSNumber:
            // JSONSerialization returns NSNumber for both integers and booleans,
            // and `NSNumber(1) as? Bool` succeeds — so a plain `case let bool as
            // Bool` silently rewrites every 0 or 1 integer as "false"/"true".
            // The CoreFoundation type is the only reliable discriminator.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        default:
            guard let value,
                  let data = try? JSONSerialization.data(
                      withJSONObject: value,
                      options: [.withoutEscapingSlashes, .fragmentsAllowed]
                  )
            else { return String(describing: value ?? "") }
            return String(decoding: data, as: UTF8.self)
        }
    }

    // MARK: Rendering

    /// Renders rows straight to CSV or a Markdown table.
    ///
    /// The public door onto the same RFC 4180 escaping the emitter uses. A tool
    /// writing a table to a *file* rather than to stdout would otherwise have
    /// to reimplement quoting, and a second implementation is a second thing to
    /// get wrong on a document someone opens in a spreadsheet.
    ///
    /// - Parameters:
    ///   - columns: Header names, in order.
    ///   - rows: Cell values, positionally matching `columns`. Short rows are
    ///     padded; long ones truncated, so a ragged row cannot shift another
    ///     record's values into the wrong column.
    ///   - format: ``OutputFormat/csv`` or ``OutputFormat/markdown``.
    public static func render(columns: [String], rows: [[String]], as format: OutputFormat) -> String {
        let keyed = rows.map { row -> [String: String] in
            var record: [String: String] = [:]
            for (index, column) in columns.enumerated() {
                record[column] = index < row.count ? row[index] : ""
            }
            return record
        }
        return Table(columns: columns, rows: keyed).render(as: format)
    }

    /// Renders the table in the requested tabular format.
    func render(as format: OutputFormat) -> String {
        guard !columns.isEmpty else { return "" }
        switch format {
        case .csv: return renderCSV()
        case .markdown: return renderMarkdown()
        default: return ""
        }
    }

    /// RFC 4180: comma-delimited, CRLF-terminated, quotes doubled.
    private func renderCSV() -> String {
        var out = columns.map(Self.csvField).joined(separator: ",") + "\r\n"
        for row in rows {
            out += columns.map { Self.csvField(row[$0] ?? "") }.joined(separator: ",") + "\r\n"
        }
        return out
    }

    /// Quotes a field when it contains a delimiter, quote, or line break, and
    /// defuses formula injection.
    private static func csvField(_ value: String) -> String {
        // A leading =, +, @, - or tab makes a spreadsheet *execute* the cell
        // rather than display it, and these cells carry scraped web content by
        // design. A leading apostrophe forces text mode; plain numbers are left
        // alone so numeric columns keep importing as numbers.
        var field = value
        if let first = field.first, first == "=" || first == "+" || first == "@" || first == "-" || first == "\t",
           Double(field) == nil {
            field = "'" + field
        }
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A GitHub-flavoured Markdown table.
    private func renderMarkdown() -> String {
        var out = "| " + columns.map(Self.markdownCell).joined(separator: " | ") + " |\n"
        out += "| " + columns.map { _ in "---" }.joined(separator: " | ") + " |\n"
        for row in rows {
            out += "| " + columns.map { Self.markdownCell(row[$0] ?? "") }.joined(separator: " | ") + " |\n"
        }
        return out
    }

    /// Escapes pipes and flattens line breaks so one cell cannot break the row.
    private static func markdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
    }
}
