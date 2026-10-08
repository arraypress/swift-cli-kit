//
//  Terminal+PipedText.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension Terminal {

    /// Piped stdin as text, without the ONE newline a pipe ends with.
    ///
    /// `echo hello | tool` hands over `"hello\n"`, and a tool that sends,
    /// types or stores that text puts the newline where nobody wanted it —
    /// measured, in the middle of a shortcut's output. Exactly one is dropped,
    /// the way the shell's `$(…)` drops it, so text that really ends in blank
    /// lines keeps the rest.
    ///
    /// `"\r\n"` is ONE Character in Swift, so a single `dropLast()` takes a
    /// CRLF ending whole; `dropLast(2)` would take the last letter with it.
    ///
    /// - Returns: `nil` when nothing was piped, or the pipe was empty.
    static func pipedText() -> String? {
        pipedStdin().map(trimmingFinalNewline)
    }

    /// Text without one final newline, LF or CRLF.
    static func trimmingFinalNewline(_ text: String) -> String {
        guard let last = text.last, last == "\n" || last == "\r\n" else { return text }
        return String(text.dropLast())
    }
}
