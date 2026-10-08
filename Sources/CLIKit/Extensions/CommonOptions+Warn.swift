//
//  CommonOptions+Warn.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension CommonOptions {

    /// Writes `warning: <message>` to standard error, unless `--quiet` was
    /// passed — the flag's documented job.
    func warn(_ message: String) {
        guard !quiet else { return }
        Terminal.warn(message)
    }
}
