//
//  ChildOutput+Text.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension ChildOutput {

    /// Whether it exited 0 on its own: no signal, no timeout.
    var succeeded: Bool { status == 0 && !signalled && !timedOut }

    /// Standard output as UTF-8 text, untrimmed.
    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }

    /// Standard error as UTF-8 text, untrimmed.
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}
