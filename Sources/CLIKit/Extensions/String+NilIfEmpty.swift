//
//  String+NilIfEmpty.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

extension String {

    /// `nil` when the string is empty or only whitespace.
    ///
    /// Manifest fields are optional in the JSON but arrive as empty strings
    /// from the parser, and an empty `abstract` should be absent rather than
    /// present-and-blank.
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
