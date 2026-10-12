//
//  InProcessInvocation.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import ArgumentParser
import Foundation

/// A tool whose MCP server runs some commands inside its own process, so what
/// they load — a model, most often — stays loaded between requests.
///
/// The default re-runs the binary for every call (``MCPCommand``), which is
/// the safe choice: nothing a command prints can reach the protocol channel.
/// It is also a cold start every time, which for a tool that loads a 13 GB
/// model is the whole cost of the call. A command listed here runs in-process
/// instead, with its standard output captured; it must write only through
/// `Terminal` and the `Emitter` (never a bare `print`) and must be safe to run
/// more than once in one process.
public protocol MCPKeepsWarm {
    /// The first path component of each command to run in-process, e.g. `["make"]`.
    static var warmCommands: Set<String> { get }
}

/// Runs a command in this process for the MCP server, as a subprocess would
/// have: its stdout, the error envelope on stderr, and the exit code.
enum InProcessInvocation {

    static func run<Root: ParsableCommand>(_ root: Root.Type, _ arguments: [String]) -> MCPServer.CommandResult {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        // The server's loop is synchronous; the command is async. A detached
        // task runs it off this thread while the loop waits.
        Task.detached {
            box.result = await outcome(root, arguments)
            done.signal()
        }
        done.wait()
        return box.result ?? MCPServer.CommandResult(stdout: "", stderr: "no result", exitCode: CLIExitCode.upstream.rawValue)
    }

    static func outcome<Root: ParsableCommand>(_ root: Root.Type, _ arguments: [String]) async -> MCPServer.CommandResult {
        do {
            let (_, stdout) = try await Terminal.capturingStandardOutput {
                var command = try root.parseAsRoot(arguments)
                if var asyncCommand = command as? AsyncParsableCommand {
                    try await asyncCommand.run()
                } else {
                    try command.run()
                }
            }
            return MCPServer.CommandResult(stdout: stdout, stderr: "", exitCode: CLIExitCode.ok.rawValue)
        } catch let error as CLIError {
            return MCPServer.CommandResult(stdout: "", stderr: error.jsonEnvelope, exitCode: error.code.exitCode.rawValue)
        } catch {
            let usage = root.exitCode(for: error) == ExitCode.validationFailure
            return MCPServer.CommandResult(
                stdout: "", stderr: root.fullMessage(for: error),
                exitCode: usage ? CLIExitCode.usage.rawValue : CLIExitCode.upstream.rawValue)
        }
    }

    private final class ResultBox: @unchecked Sendable {
        var result: MCPServer.CommandResult?
    }
}
