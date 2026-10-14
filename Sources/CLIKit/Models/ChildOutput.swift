//
//  ChildOutput.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a finished child process left: how it ended and what it wrote.
public struct ChildOutput: Sendable, Equatable {

    /// The exit status — or, when ``signalled``, the number of the signal
    /// that ended it.
    public let status: Int32

    /// Whether a signal ended it rather than an exit.
    public let signalled: Bool

    /// Whether the timeout passed and the child was stopped.
    public let timedOut: Bool

    /// Its standard output, as ``ChildCapture`` kept it.
    public let stdout: Data

    /// Its standard error, as ``ChildCapture`` kept it.
    public let stderr: Data

    public init(status: Int32, signalled: Bool = false, timedOut: Bool = false, stdout: Data = Data(), stderr: Data = Data()) {
        self.status = status
        self.signalled = signalled
        self.timedOut = timedOut
        self.stdout = stdout
        self.stderr = stderr
    }
}
