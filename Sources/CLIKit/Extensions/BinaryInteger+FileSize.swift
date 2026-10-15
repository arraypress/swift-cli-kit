//
//  BinaryInteger+FileSize.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension BinaryInteger {

    /// A byte count as Finder writes it: `21 KB`, `7.7 MB`.
    ///
    /// `ByteCountFormatter` in its `.file` style — decimal units, the way the
    /// Finder and every Apple app count. Every tool that printed a size wrote
    /// this same call; this is the one place it is written. Nothing reads
    /// `0 bytes`, not the formatter's own "Zero KB".
    var fileSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(clamping: self))
    }
}
