//
//  String+IsBlank.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension String {

    /// Whether the string is empty or only whitespace.
    ///
    /// A JSON field left as `""`, a `"  "` typed by mistake and an absent
    /// value all mean the same thing to a tool deciding whether to draw a
    /// line for it, and `isEmpty` only catches the first.
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
