//
//  ChildProcess.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Running another program and reading what it says, safely. Every tool that
//  shells out — osascript, git, launchctl, uv, MuseScore — wrote this by hand,
//  and the hand-written copies share two traps:
//
//  - reading after `waitUntilExit()`, or reading stdout to its end before
//    stderr: the child blocks once it has written a pipe buffer (64 KB) that
//    nobody is reading, and both sides wait for ever;
//  - reading both pipes through `FileHandle.bytes`: Foundation serves every
//    `bytes` sequence from one serial queue, so one quiet stream stalls the
//    other (imagine train's progress sat unread for half an hour).
//
//  This reads both pipes with `readabilityHandler` as data arrives, feeds
//  stdin from its own thread, and never inherits the parent's stdin.
//

import Foundation

/// Runs a program with its output read safely.
///
/// ```swift
/// let result = try ChildProcess.runBlocking("/usr/bin/git", ["status", "--porcelain"], directory: root)
/// guard result.succeeded else { throw … result.stderrText … }
///
/// // A long job: progress line by line, only the end of stderr kept.
/// let result = try await ChildProcess.run(uv, arguments, stderr: .lastLines(12),
///                                         onStdout: { print($0) })
/// ```
///
/// Arguments are passed as an array — never a shell line. A child that ran
/// and failed is not an error: read ``ChildOutput/status``. Line callbacks
/// run on a background queue, each stream's in order, the two streams
/// possibly at the same time; a line ends at `\n`, `\r\n` or a lone `\r`.
public enum ChildProcess {

    /// How long a stopped child gets between SIGTERM and SIGKILL.
    public static let killGrace: Double = 3

    /// How long the streams are waited for once the child has exited. They
    /// end at once unless a grandchild inherited them and lives on.
    static let drainGrace: Double = 2

    /// Runs `executable` and suspends until it has finished.
    ///
    /// Cancelling the task stops the child (SIGTERM, then SIGKILL after
    /// ``killGrace``) and throws ``ChildProcessError/cancelled`` once it has
    /// been reaped.
    ///
    /// - Parameters:
    ///   - executable: The program — an absolute path, never looked up on PATH.
    ///   - arguments: Its arguments, each passed as it is.
    ///   - environment: Its whole environment; `nil` inherits this process's.
    ///   - directory: Its working directory; `nil` inherits this process's.
    ///   - input: Written to its stdin, which is then closed; `nil` gives it
    ///     `/dev/null`.
    ///   - timeout: Seconds before it is stopped; the output then says
    ///     ``ChildOutput/timedOut`` and holds what arrived.
    ///   - stdout: How much of stdout the result keeps.
    ///   - stderr: How much of stderr the result keeps.
    ///   - started: Called once it is running, with the `Process`.
    ///   - onStdout: Called with each stdout line as it arrives.
    ///   - onStderr: Called with each stderr line as it arrives.
    public static func run(
        _ executable: URL,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        directory: URL? = nil,
        input: Data? = nil,
        timeout: Double? = nil,
        stdout: ChildCapture = .all,
        stderr: ChildCapture = .all,
        started: (@Sendable (Process) -> Void)? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws(ChildProcessError) -> ChildOutput {
        guard !Task.isCancelled else { throw .cancelled }
        let run = ChildRun(
            executable: executable, arguments: arguments, environment: environment, directory: directory,
            input: input, stdout: stdout, stderr: stderr, onStdout: onStdout, onStderr: onStderr,
            drainGrace: drainGrace, killGrace: killGrace
        )
        try run.start(timeout: timeout)
        started?(run.process)
        await withTaskCancellationHandler {
            await run.wait()
        } onCancel: {
            run.stop(.cancelled)
        }
        if run.stopReason == .cancelled { throw .cancelled }
        return run.output
    }

    /// Runs the program at `path`; see the async `run`.
    public static func run(
        _ path: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        directory: URL? = nil,
        input: Data? = nil,
        timeout: Double? = nil,
        stdout: ChildCapture = .all,
        stderr: ChildCapture = .all,
        started: (@Sendable (Process) -> Void)? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws(ChildProcessError) -> ChildOutput {
        try await run(
            URL(fileURLWithPath: path), arguments, environment: environment, directory: directory,
            input: input, timeout: timeout, stdout: stdout, stderr: stderr, started: started,
            onStdout: onStdout, onStderr: onStderr
        )
    }

    /// Runs `executable` and blocks the calling thread until it has
    /// finished — for synchronous code (osascript, git, launchctl wrappers).
    /// From async code prefer the async `run`,
    /// which does not hold a thread and can be cancelled.
    ///
    /// The parameters are the async version's.
    public static func runBlocking(
        _ executable: URL,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        directory: URL? = nil,
        input: Data? = nil,
        timeout: Double? = nil,
        stdout: ChildCapture = .all,
        stderr: ChildCapture = .all,
        started: (@Sendable (Process) -> Void)? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) throws(ChildProcessError) -> ChildOutput {
        try runBlocking(
            executable, arguments, environment: environment, directory: directory, input: input,
            timeout: timeout, stdout: stdout, stderr: stderr, started: started,
            onStdout: onStdout, onStderr: onStderr, drainGrace: drainGrace
        )
    }

    /// Runs the program at `path`, blocking; see the URL `runBlocking`.
    public static func runBlocking(
        _ path: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        directory: URL? = nil,
        input: Data? = nil,
        timeout: Double? = nil,
        stdout: ChildCapture = .all,
        stderr: ChildCapture = .all,
        started: (@Sendable (Process) -> Void)? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) throws(ChildProcessError) -> ChildOutput {
        try runBlocking(
            URL(fileURLWithPath: path), arguments, environment: environment, directory: directory,
            input: input, timeout: timeout, stdout: stdout, stderr: stderr, started: started,
            onStdout: onStdout, onStderr: onStderr
        )
    }

    /// The blocking run with the drain grace exposed — the seam the tests use.
    static func runBlocking(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]?,
        directory: URL?,
        input: Data?,
        timeout: Double?,
        stdout: ChildCapture,
        stderr: ChildCapture,
        started: (@Sendable (Process) -> Void)?,
        onStdout: (@Sendable (String) -> Void)?,
        onStderr: (@Sendable (String) -> Void)?,
        drainGrace: Double
    ) throws(ChildProcessError) -> ChildOutput {
        let run = ChildRun(
            executable: executable, arguments: arguments, environment: environment, directory: directory,
            input: input, stdout: stdout, stderr: stderr, onStdout: onStdout, onStderr: onStderr,
            drainGrace: drainGrace, killGrace: killGrace
        )
        try run.start(timeout: timeout)
        started?(run.process)
        run.waitBlocking()
        return run.output
    }
}
