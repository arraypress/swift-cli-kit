//
//  ChildCapture.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How much of one of a child process's output streams ``ChildProcess``
/// keeps for the result. The stream is always read to its end either way —
/// an unread pipe is what blocks a child — this only decides what is held.
public enum ChildCapture: Sendable, Equatable {

    /// Every byte.
    case all

    /// Nothing: the stream is drained and dropped (line callbacks still run).
    case none

    /// The last `n` lines, joined with `\n` — what a failure message quotes,
    /// without holding a long job's whole log in memory.
    case lastLines(Int)
}
