//
//  CommonOptions.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The flags every tool in the family shares, so `--json`, `--fields` and
//  `--quiet` mean the same thing everywhere.
//

import ArgumentParser
import Foundation

/// Flags every CLIKit tool accepts.
///
/// Kept identical across all of them on purpose: a caller that has learned one
/// tool has learned the rest, which matters a great deal more when the tools
/// number in the dozens and the caller is a language model reading `--help`.
public struct CommonOptions: ParsableArguments {

    public init() {}

    @Flag(name: .long, help: "Force JSON output (the default when piped).")
    public var json: Bool = false

    @Flag(name: .long, help: "Force human-readable text output.")
    public var text: Bool = false

    @Flag(name: .long, help: "Emit one JSON document per line.")
    public var ndjson: Bool = false

    @Flag(name: .long, help: "Emit CSV with a header row.")
    public var csv: Bool = false

    @Flag(name: .long, help: "Emit a Markdown table.")
    public var markdown: Bool = false

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: ArgumentHelp(
            "Limit output to these top-level fields.",
            discussion: "Unknown names are ignored. Cuts response size sharply for large payloads."
        )
    )
    public var fields: [String] = []

    @Flag(name: .long, help: "Return every available field rather than the curated subset.")
    public var full: Bool = false

    @Flag(name: .long, help: "Bypass the on-disk cache for this request.")
    public var noCache: Bool = false

    @Flag(name: .long, help: "Suppress warnings on stderr.")
    public var quiet: Bool = false

    /// The resolved output format, honouring the explicit flags.
    public var format: OutputFormat {
        if csv { return .csv }
        if markdown { return .markdown }
        if ndjson { return .ndjson }
        if json { return .json }
        if text { return .text }
        return OutputFormat.resolve(explicit: nil)
    }

    /// An emitter configured from these options.
    public var emitter: Emitter {
        Emitter(format: format, fields: fields.isEmpty ? nil : fields, quiet: quiet)
    }

    /// Rejects mutually exclusive format flags.
    public func validate() throws {
        let chosen = [json, text, ndjson, csv, markdown].filter { $0 }.count
        if chosen > 1 {
            throw ValidationError("Pass at most one of --json, --text, --ndjson, --csv, --markdown.")
        }
    }
}
