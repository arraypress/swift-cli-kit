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

    /// A GitHub-flavoured Markdown table.
    case markdown

    /// Whether this format renders records as a table of scalar columns.
    ///
    /// Tabular formats cannot represent nesting, so nested values are
    /// JSON-encoded into their cell rather than dropped.
    var isTabular: Bool {
        self == .csv || self == .markdown
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
