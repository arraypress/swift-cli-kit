//
//  Error+CLIMessage.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension Error {

    /// The one-line message a failure is reported with: a ``CLIError``'s own
    /// message, or `localizedDescription` for anything else.
    ///
    /// A batch that keeps going past one bad input reports the reason beside
    /// the input's name, and the reason for a ``CLIError`` is its message,
    /// not the "The operation couldn't be completed" Foundation wraps around
    /// any error it did not make itself.
    var cliMessage: String {
        (self as? CLIError)?.message ?? localizedDescription
    }
}
