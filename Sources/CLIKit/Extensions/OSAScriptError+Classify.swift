//
//  OSAScriptError+Classify.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  How a finished osascript becomes an error — exit code, wording and retry
//  verdict — as pure functions over its output.
//

import Foundation

extension OSAScriptError {

    /// The error a finished run represents, or `nil` when it succeeded.
    static func classify(_ output: ChildOutput, timeout: Double) -> OSAScriptError? {
        if output.timedOut {
            return OSAScriptError(reason: .timedOut(seconds: timeout), retry: .mayHaveCompleted)
        }
        guard !output.succeeded else { return nil }
        let message = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = errorNumber(in: message)
        return OSAScriptError(
            reason: .failed(status: output.status, number: number, message: message),
            retry: output.signalled ? .mayHaveCompleted : verdict(number: number, message: message)
        )
    }

    /// The `(-1743)` osascript ends an error line with.
    static func errorNumber(in message: String) -> Int? {
        guard let open = message.lastIndex(of: "("), let close = message.lastIndex(of: ")"), open < close,
              message[close...].dropFirst().allSatisfy(\.isWhitespace)
        else { return nil }
        return Int(message[message.index(after: open)..<close])
    }

    /// Whether a failure could have happened after the script acted.
    ///
    /// Only failures that provably precede any effect say "not started": the
    /// script did not compile, the user's permission was refused, or the app
    /// was not running to receive the event. Anything else happened somewhere
    /// inside a script that may already have done its work.
    static func verdict(number: Int?, message: String) -> RetryVerdict {
        if message.localizedCaseInsensitiveContains("syntax error") { return .notStarted }
        switch number {
        case -1743, -1744, -600, -2740, -2741, -2753: return .notStarted
        default: return .mayHaveCompleted
        }
    }

    /// The family code a failure leaves with.
    var code: CLIError.Code {
        switch reason {
        case .couldNotStart, .timedOut: return .upstream
        case .failed(_, let number, let message):
            if message.localizedCaseInsensitiveContains("syntax error") { return .parseFailure }
            switch number {
            case -1743, -1744: return .authRequired
            case -1728, -1719: return .notFound
            case -2740, -2741, -2753: return .parseFailure
            default: return .upstream
            }
        }
    }
}

extension OSAScriptError: CLIErrorDescribing {

    public var cliError: CLIError {
        switch reason {
        case .couldNotStart(let why):
            return CLIError(code: code, message: "could not run osascript: \(why)", retry: retry)
        case .timedOut(let seconds):
            return CLIError(
                code: code,
                message: "AppleScript did not finish within \(Self.seconds(seconds)) and was stopped",
                hint: "the app may be busy or showing a dialog — look at it before retrying; "
                    + "if it is only slow, set \(OSAScript.timeoutEnvironmentKey) to more seconds",
                retry: retry
            )
        case .failed(let status, let number, let message):
            let words = message.isEmpty ? "osascript exited \(status)" : message
            let hint: String? = switch number {
            case -1743, -1744:
                "allow this app to control the target in System Settings › Privacy & Security › Automation"
            case -600:
                "the app is not running; open it and try again"
            default:
                nil
            }
            return CLIError(code: code, message: "AppleScript failed: \(words)", hint: hint, retry: retry)
        }
    }

    /// `15 s`, `2.5 s`.
    private static func seconds(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) s" : "\(value) s"
    }
}

extension OSAScriptError: LocalizedError {

    public var errorDescription: String? { cliError.message }
}
