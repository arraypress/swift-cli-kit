//
//  Terminal+Confirm.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension Terminal {

    /// Asks a yes/no question on the terminal, defaulting to no.
    ///
    /// For the verbs with nothing to put back afterwards — deleting an event,
    /// cancelling a booking that emails somebody. With `assumeYes` (a tool's
    /// `--yes`) it does not ask.
    ///
    /// **Refuses rather than hangs when nobody can answer.** An agent or a
    /// script has no terminal on stdin; reading one there would wait for ever
    /// or read the next line of a pipe as the answer. So without a terminal
    /// this throws a usage error naming `--yes` instead.
    ///
    /// - Parameters:
    ///   - question: The question, without the `[y/N]`.
    ///   - assumeYes: Skip asking — the caller already said yes.
    ///   - read: Reads the answer. Injected so tests need no terminal.
    /// - Returns: Whether the answer was `y` or `yes`, any case.
    static func confirm(
        _ question: String,
        assumeYes: Bool,
        isInteractive: Bool = isatty(STDIN_FILENO) == 1,
        read: () -> String? = { readLine() }
    ) throws -> Bool {
        if assumeYes { return true }
        guard isInteractive else {
            throw CLIError.usage("cannot ask “\(question)” without a terminal", hint: "pass --yes to confirm")
        }
        writeError("\(question) [y/N] ")
        let answer = read()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return answer == "y" || answer == "yes"
    }
}
