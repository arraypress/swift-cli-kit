//
//  Array+NilIfEmpty.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

extension Array {

    /// `nil` when the array is empty.
    ///
    /// An absent key and an empty array mean different things to a caller
    /// reading the manifest: "this command takes no arguments" versus "we did
    /// not look".
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
