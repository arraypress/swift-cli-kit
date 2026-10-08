//
//  Files+Available.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension Files {

    /// Where a file can be saved without overwriting anything: `name.jpg`, or
    /// `name 2.jpg`, `name 3.jpg` … when that is taken.
    ///
    /// The way the Finder numbers a copy. For copying OUT — attachments,
    /// exports — where two sources routinely share a name (`invoice.pdf`) and
    /// overwriting the first with the second loses a file nobody asked to
    /// lose.
    ///
    /// - Parameters:
    ///   - name: The file name wanted.
    ///   - folder: Where it goes.
    ///   - exists: Whether a path is taken. Injected so tests need no disk.
    static func availableURL(
        for name: String,
        in folder: URL,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while exists(candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
