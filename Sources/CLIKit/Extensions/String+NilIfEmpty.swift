//
//  String+NilIfEmpty.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension String {

    /// `nil` when the string is empty; the string otherwise.
    ///
    /// For a payload field that is optional in the JSON but arrives as `""`
    /// from an API — absent reads better than present-and-blank. Six tools
    /// carried this line privately. Whitespace counts as content here; use
    /// ``nilIfBlank`` when it should not.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
