//
//  OutputFormat.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  How results are serialised to standard output.
//

import Foundation

/// How results are serialised to standard output.
public enum OutputFormat: String, Sendable, CaseIterable {

    /// A single JSON document.
    case json

    /// One JSON document per line. Suited to batch results a caller wants to
    /// stream rather than buffer.
    case ndjson

    /// Human-readable plain text.
    case text

    /// RFC 4180 comma-separated values, with a header row.
    case csv

    /// Tab-separated values, with a header row.
    ///
    /// The clipboard format: a spreadsheet pastes tab-separated text straight
    /// into cells, where pasted CSV lands in a single column and has to be
    /// run through an import dialog. `tool --tsv | pb copy` is one step.
    case tsv

    /// A GitHub-flavoured Markdown table.
    case markdown

    /// An HTML table, for a report that is going to be opened in a browser
    /// or pasted into a document.
    case html

    /// Whether this format renders as a table of rows rather than as records.
    public var isTabular: Bool {
        switch self {
        case .csv, .tsv, .markdown, .html: true
        case .json, .ndjson, .text: false
        }
    }

    /// Picks a format, honouring an explicit choice and otherwise inferring one
    /// from whether stdout is a terminal.
    ///
    /// The default matters more than it looks: an agent shelling out gets
    /// parseable JSON with no flag, and a person running the same command gets
    /// something readable. Neither has to know the other's mode exists.
    ///
    /// - Parameter explicit: A format the user asked for, or `nil` to infer.
    public static func resolve(explicit: OutputFormat?) -> OutputFormat {
        if let explicit { return explicit }
        return Terminal.stdoutIsTTY ? .text : .json
    }
}
