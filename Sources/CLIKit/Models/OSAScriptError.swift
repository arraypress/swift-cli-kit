//
//  OSAScriptError.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why an ``OSAScript`` run failed, and whether it may have acted first.
public struct OSAScriptError: Error, Equatable, Sendable {

    /// What happened.
    public enum Reason: Equatable, Sendable {
        /// osascript could not be launched.
        case couldNotStart(String)
        /// The limit passed and the child was killed.
        case timedOut(seconds: Double)
        /// It ran and failed: its exit status, the AppleScript error number
        /// when it printed one (`-1743`), and its own words.
        case failed(status: Int32, number: Int?, message: String)
    }

    public let reason: Reason

    /// Whether running it again is safe. A timeout or a runtime error says
    /// ``RetryVerdict/mayHaveCompleted``: the script had reached the app.
    /// Failing to launch, a compile error, a refused permission or an app
    /// that is not running say ``RetryVerdict/notStarted``.
    public let retry: RetryVerdict

    public init(reason: Reason, retry: RetryVerdict) {
        self.reason = reason
        self.retry = retry
    }

    /// The AppleScript error number, when there is one.
    public var number: Int? {
        if case .failed(_, let number, _) = reason { return number }
        return nil
    }
}
