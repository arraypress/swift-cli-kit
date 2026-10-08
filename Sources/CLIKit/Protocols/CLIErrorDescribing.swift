//
//  CLIErrorDescribing.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Lets a tool say everything a library's error should become — code,
//  message and hint — not just which code it deserves.
//

import Foundation

/// An error that knows the whole ``CLIError`` it should leave as.
///
/// ``CLIErrorConvertible`` names a code and keeps the library's own words.
/// That is enough when the library already speaks to a caller. It is not
/// when the tool has something to add: a missing permission that should name
/// the Settings pane, a timeout that should point at a prompt, a refusal whose
/// wording mentions a library parameter the CLI calls something else. Tools
/// used to override `run()` for that, each catching its library's error by
/// hand; conforming here does the same in one property, and the default
/// `run()` finds it.
///
/// ```swift
/// extension ShortcutsError: @retroactive CLIErrorDescribing {
///     public var cliError: CLIError { Failure.describing(self) }
/// }
/// ```
///
/// A described error with no ``CLIError/service`` is given the command's.
public protocol CLIErrorDescribing: Error {

    /// The error this one becomes.
    var cliError: CLIError { get }
}
