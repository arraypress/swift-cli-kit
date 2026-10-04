//
//  CLIErrorConvertible.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Lets a tool say which family code a library's error deserves.
//  Libraries don't depend on CLIKit, so the conformance lives in the tool.
//

import Foundation

/// An error that knows which family code it deserves.
///
/// Without this, ``CLIError/wrapping(_:service:)`` doesn't recognise a
/// library's own error type and falls back to ``CLIError/Code/upstream``,
/// telling the caller to retry. That's right for a network failure. It's
/// wrong for a file that isn't an image or a date that isn't a date, which
/// will fail the same way every time.
///
/// Conform the library's error type in the tool:
///
/// ```swift
/// extension ImageForgeError: CLIErrorConvertible {
///     public var cliErrorCode: CLIError.Code {
///         switch self {
///         case .unreadable: .parseFailure
///         case .writeFailed: .upstream
///         }
///     }
/// }
/// ```
///
/// The message is the error's `errorDescription` when it is a
/// `LocalizedError`, and its `description` otherwise.
public protocol CLIErrorConvertible: Error {

    /// The code this error leaves with.
    var cliErrorCode: CLIError.Code { get }

    /// A next step for the caller, if there is one.
    var cliErrorHint: String? { get }
}

public extension CLIErrorConvertible {

    var cliErrorHint: String? { nil }
}
