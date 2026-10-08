//
//  Terminal+Warn.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The fleet's one way to say "this went through, but look". Thirty-odd
//  tools wrote `warning:` to stderr by hand, most straight through
//  FileHandle — which raises an uncatchable exception on a closed stderr,
//  where ``Terminal/writeError(_:)`` does not — and only three of them
//  honoured `--quiet`, which CommonOptions documents as the flag that
//  silences warnings.
//

import Foundation

public extension Terminal {

    /// Writes `warning: <message>` to standard error.
    ///
    /// For code with no ``CommonOptions`` in reach — a helper deep in a
    /// support file. A command should call ``CommonOptions/warn(_:)`` instead,
    /// so `--quiet` is honoured.
    static func warn(_ message: String) {
        writeError("warning: \(message)")
    }
}
