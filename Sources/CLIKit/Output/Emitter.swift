//
//  Emitter.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Writes a payload in the resolved format.
//

import Foundation

/// Serialises results to standard output in the resolved format.
public struct Emitter: Sendable {

    /// The format to write.
    public let format: OutputFormat

    /// Top-level keys to keep, or `nil` for all of them.
    public let fields: [String]?

    /// Whether to pretty-print JSON.
    ///
    /// Defaults to true only for a terminal. Piped output is compact, which is
    /// not merely tidier — for an agent paying by the token, the whitespace in a
    /// pretty-printed response is pure cost.
    public let pretty: Bool

    /// Whether to suppress the stderr warning about an empty field selection.
    public let quiet: Bool

    public init(
        format: OutputFormat,
        fields: [String]? = nil,
        pretty: Bool? = nil,
        quiet: Bool = false
    ) {
        self.format = format
        self.fields = fields.map(Self.normalise)
        self.pretty = pretty ?? Terminal.stdoutIsTTY
        self.quiet = quiet
    }

    /// Splits comma-joined field names and trims each one.
    ///
    /// `--fields` parses up to the next option, so space-separated names arrive
    /// as separate values — but `--fields title,author` is the form most people
    /// type, and it arrived as the single name `"title,author"`, which matched
    /// nothing. The result was an empty object and exit 0: a mistake that
    /// looked like a successful answer, which is the one outcome this family
    /// tries hardest to avoid.
    private static func normalise(_ fields: [String]) -> [String] {
        fields
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Encoding

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Sorted keys keep output byte-stable across runs, which callers rely on
        // for diffing and cache keys.
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: Emitting

    /// Writes a single result.
    ///
    /// - Parameter value: The payload. Rendered as text when the resolved
    ///   format is ``OutputFormat/text``, otherwise as JSON.
    public func emit<T: Encodable & TextRenderable>(_ value: T) throws {
        switch format {
        case .text:
            Terminal.writeLine(value.renderText())
        case .csv, .markdown:
            let data = try encoder.encode(value)
            Terminal.write(Table(from: applyFieldFilter(to: data)).render(as: format))
        case .json, .ndjson:
            let data = try encoder.encode(value)
            Terminal.writeLine(String(decoding: applyFieldFilter(to: data), as: UTF8.self))
        }
    }

    /// Writes a sequence of results.
    ///
    /// In ``OutputFormat/ndjson`` each element becomes its own line, so a caller
    /// can process them as they arrive instead of waiting for the whole batch.
    public func emitAll<T: Encodable & TextRenderable>(_ values: [T]) throws {
        switch format {
        case .text:
            for value in values { Terminal.writeLine(value.renderText()) }
        case .csv, .markdown:
            let data = try encoder.encode(values)
            Terminal.write(Table(from: applyFieldFilter(to: data)).render(as: format))
        case .ndjson:
            let lineEncoder = encoder
            lineEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            for value in values {
                let data = try lineEncoder.encode(value)
                Terminal.writeLine(String(decoding: applyFieldFilter(to: data), as: UTF8.self))
            }
        case .json:
            let data = try encoder.encode(values)
            Terminal.writeLine(String(decoding: applyFieldFilter(to: data), as: UTF8.self))
        }
    }

    /// Writes a sequence of results that render as table rows.
    ///
    /// Overloads ``emitAll(_:)`` for ``TableRenderable`` payloads: in text mode
    /// they become an aligned table rather than ragged lines. Every other format
    /// behaves identically, so adopting the protocol changes only what a person
    /// sees.
    public func emitAll<T: Encodable & TableRenderable>(_ values: [T]) throws {
        guard format == .text else {
            try emitAll(values, asNonTable: ())
            return
        }
        guard !values.isEmpty else { return }

        Terminal.writeLine(
            TextTable.render(
                columns: T.tableColumns,
                rows: values.map(\.tableRow),
                flexible: T.flexibleColumns
            )
        )
    }

    /// The non-tabular path, kept reachable from the table overload.
    private func emitAll<T: Encodable & TextRenderable>(_ values: [T], asNonTable: Void) throws {
        switch format {
        case .text:
            for value in values { Terminal.writeLine(value.renderText()) }
        case .csv, .markdown:
            let data = try encoder.encode(values)
            Terminal.write(Table(from: applyFieldFilter(to: data)).render(as: format))
        case .ndjson:
            let lineEncoder = encoder
            lineEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            for value in values {
                let data = try lineEncoder.encode(value)
                Terminal.writeLine(String(decoding: applyFieldFilter(to: data), as: UTF8.self))
            }
        case .json:
            let data = try encoder.encode(values)
            Terminal.writeLine(String(decoding: applyFieldFilter(to: data), as: UTF8.self))
        }
    }

    // MARK: Field Selection

    /// Narrows encoded JSON to the requested top-level keys.
    ///
    /// Applied post-encode against the serialised object rather than at the
    /// `Encodable` layer, so it works uniformly for every payload type without
    /// each one having to implement selection itself. Arrays are filtered
    /// element-wise.
    ///
    /// Unknown key names are ignored rather than rejected — a caller narrowing
    /// output across several services should not have to know which fields each
    /// one happens to expose. When *every* name is unknown the result would be
    /// an empty object with exit 0, so that case warns on stderr and names the
    /// fields that do exist.
    private func applyFieldFilter(to data: Data) -> Data {
        guard let fields, !fields.isEmpty else { return data }
        let wanted = Set(fields)

        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return data }

        var available = Set<String>()

        func filter(_ object: Any) -> Any {
            if let dictionary = object as? [String: Any] {
                available.formUnion(dictionary.keys)
                return dictionary.filter { wanted.contains($0.key) }
            }
            if let array = object as? [Any] {
                return array.map(filter)
            }
            return object
        }

        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }

        let filtered = filter(parsed)

        if !quiet, !available.isEmpty, wanted.isDisjoint(with: available) {
            Terminal.writeError(
                "warning: --fields matched nothing; this payload has: "
                    + available.sorted().joined(separator: ", ")
            )
        }

        guard let reduced = try? JSONSerialization.data(withJSONObject: filtered, options: options) else {
            return data
        }
        return reduced
    }
}

// MARK: - Error Reporting

public extension Emitter {

    /// Writes a failure to standard error and returns its exit code.
    ///
    /// The JSON envelope goes to stderr even in text mode when stderr is not a
    /// terminal, so a caller that redirects the two streams separately always
    /// gets something parseable.
    @discardableResult
    static func report(_ error: CLIError) -> CLIExitCode {
        if Terminal.stderrIsTTY {
            Terminal.writeError(error.humanDescription)
        } else {
            Terminal.writeError(error.jsonEnvelope)
        }
        return error.code.exitCode
    }
}
