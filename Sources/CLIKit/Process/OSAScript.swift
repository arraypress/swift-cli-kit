//
//  OSAScript.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Running AppleScript (or JXA) through osascript, the one way the fleet does.
//
//  WHAT EVERY HAND-WRITTEN COPY GOT WRONG, somewhere in the fleet:
//
//  - No timeout. An app showing a modal dialog, or waiting on a permission
//    prompt nobody can see, leaves osascript waiting for ever — and the agent
//    that called the tool with it. Here every script has a hard limit
//    (15 s unless told otherwise) after which the child is killed.
//  - Reading stdout to its end, then stderr. A script that writes a pipe
//    buffer of errors blocks, and so does the tool. ``ChildProcess`` drains
//    both as they fill.
//  - Values pasted after `-e script` with no `--`. osascript reads options
//    until the first operand, so a message that begins `-s` or `-e` is parsed
//    as a flag: `-s x` fails outright, and `-e` would run the next argument as
//    a line of script. Measured on macOS 27. A `--` ends the options.
//  - "It failed" with no word on whether it acted. A timeout after the script
//    reached the app may well have sent the message; a compile error cannot
//    have. ``OSAScriptError`` carries a ``RetryVerdict`` that says which.
//

import Foundation

/// Runs AppleScript or JavaScript for Automation through `/usr/bin/osascript`.
///
/// ```swift
/// let names = try OSAScript.run("""
///     on run argv
///         tell application "Contacts" to return name of every group
///     end run
///     """)
/// try OSAScript.run(sendScript, arguments: [text, chatID], timeout: 30)
/// ```
///
/// Values always go in as `arguments` (the script's `argv`), never spliced
/// into the source: a value with a quote or `end tell` in it is data, and an
/// escaping slip would make it code.
public enum OSAScript {

    /// The language of a script.
    public enum Language: String, Sendable {
        case appleScript = "AppleScript"
        case javaScript = "JavaScript"
    }

    /// The limit a script gets when none is given: 15 seconds. Long enough
    /// for an app to launch cold; short enough that a stuck dialog does not
    /// hang an agent.
    public static let defaultTimeout: Double = 15

    /// The environment variable that changes the default limit, in seconds —
    /// for a slow machine, or an app that is slow to launch.
    public static let timeoutEnvironmentKey = "CLIKIT_OSASCRIPT_TIMEOUT"

    /// The real osascript.
    public static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    /// Runs `source` and returns what it printed, less the one newline
    /// osascript adds.
    ///
    /// - Parameters:
    ///   - source: The script. Multi-line is fine.
    ///   - arguments: The script's `argv` — `on run argv`.
    ///   - language: AppleScript unless JXA.
    ///   - timeout: Seconds before the child is stopped (SIGTERM, then SIGKILL
    ///     3 s later); `nil` means `CLIKIT_OSASCRIPT_TIMEOUT` or 15 s.
    ///   - executable: osascript itself, or a stand-in for tests.
    ///   - started: Called with the child's process ID once it is running.
    /// - Throws: ``OSAScriptError``, which converts to a ``CLIError`` with the
    ///   right exit code and a ``RetryVerdict``.
    @discardableResult
    public static func run(
        _ source: String,
        arguments: [String] = [],
        language: Language = .appleScript,
        timeout: Double? = nil,
        executable: URL = osascript,
        started: (@Sendable (Int32) -> Void)? = nil
    ) throws(OSAScriptError) -> String {
        let limit = resolvedTimeout(timeout)
        var onStart: (@Sendable (Process) -> Void)?
        if let started {
            onStart = { @Sendable process in started(process.processIdentifier) }
        }
        let output: ChildOutput
        do throws(ChildProcessError) {
            output = try ChildProcess.runBlocking(
                executable, commandLine(source: source, arguments: arguments, language: language),
                timeout: limit, started: onStart
            )
        } catch {
            throw OSAScriptError(reason: .couldNotStart(error.reason), retry: .notStarted)
        }
        if let failure = OSAScriptError.classify(output, timeout: limit) { throw failure }
        var text = output.stdoutText
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    /// osascript's argument vector: the language, the source, `--`, then the
    /// values. The `--` is what keeps a value starting with `-` a value.
    static func commandLine(source: String, arguments: [String], language: Language) -> [String] {
        ["-l", language.rawValue, "-e", source, "--"] + arguments
    }

    /// The limit to use: the one given, else the environment's, else 15 s.
    static func resolvedTimeout(_ explicit: Double?,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> Double {
        if let explicit, explicit > 0 { return explicit }
        if let value = environment[timeoutEnvironmentKey].flatMap(Double.init), value > 0 { return value }
        return defaultTimeout
    }
}
