//
//  TableRenderable.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A payload whose rows line up in a column.
//

import Foundation

/// A result type that renders as a row in an aligned table.
///
/// Opt-in, and deliberately not universal: a community post or a comment is a
/// paragraph, and forcing one into a column would truncate the only part that
/// matters. Types that are genuinely tabular — search hits, uploads, domain
/// statuses — adopt this; the rest stay with ``TextRenderable``.
public protocol TableRenderable: TextRenderable {

    /// Column headers, in order.
    static var tableColumns: [String] { get }

    /// This value's cells, in the same order as ``tableColumns``.
    var tableRow: [String] { get }

    /// Indices of columns that may be shortened when the table is too wide.
    ///
    /// Defaults to all of them. Narrow it to protect identifiers: truncating a
    /// video ID or a domain gives the reader something they cannot copy.
    static var flexibleColumns: [Int] { get }
}

public extension TableRenderable {
    static var flexibleColumns: [Int] { Array(tableColumns.indices) }
}
