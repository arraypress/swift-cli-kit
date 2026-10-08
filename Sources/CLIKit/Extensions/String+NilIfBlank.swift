//
//  String+NilIfBlank.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension String {

    /// `nil` when the string is empty or only whitespace; the string otherwise.
    ///
    /// Manifest fields are optional in the JSON but arrive as empty strings
    /// from the parser, and an empty `abstract` should be absent rather than
    /// present-and-blank — as should one that is a stray newline.
    var nilIfBlank: String? {
        isBlank ? nil : self
    }
}
