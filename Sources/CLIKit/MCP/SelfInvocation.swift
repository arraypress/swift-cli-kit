//
//  SelfInvocation.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Re-running this binary as a subprocess, which is how MCP keeps the
//  protocol stream and a command's payload apart.
//

import ArgumentParser
import Foundation

/// Runs this same binary as a subprocess.
///
/// Used for two things: reading ArgumentParser's `--experimental-dump-help`
/// (whose types are not importable, since `ArgumentParserToolInfo` is not a
/// public product), and executing commands on behalf of the MCP server.
///
/// Re-execution rather than in-process dispatch is deliberate for MCP: stdout is
/// the protocol channel, and a command that writes its payload there would
/// corrupt the stream. A subprocess keeps the two apart, and preserves the exit
/// code and stderr envelope exactly as a shell caller would see them.
enum SelfInvocation {

    /// This binary's path.
    static var executableURL: URL {
        if let path = Bundle.main.executablePath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: CommandLine.arguments.first ?? "")
    }

    /// Runs the binary with `arguments` and captures its output.
    ///
    /// Through ``ChildProcess``: both pipes drained as they fill (a command
    /// writing more than a pipe buffer would otherwise block for ever), and
    /// never the parent's stdin — under MCP that is the protocol channel, and
    /// a child that reads it (`auth login`, or `mcp` itself) would consume
    /// protocol frames or block on them forever.
    static func run(_ arguments: [String]) -> MCPServer.CommandResult {
        do {
            let result = try ChildProcess.runBlocking(executableURL, arguments)
            return MCPServer.CommandResult(stdout: result.stdoutText, stderr: result.stderrText, exitCode: result.status)
        } catch {
            return MCPServer.CommandResult(
                stdout: "",
                stderr: "Could not run \(executableURL.path): \(error.reason)",
                exitCode: CLIExitCode.upstream.rawValue
            )
        }
    }

    /// Reads the command tree as ArgumentParser's dump-help JSON.
    static func dumpHelp() throws -> Data {
        let result = run(["--experimental-dump-help"])
        guard result.exitCode == 0, !result.stdout.isEmpty else {
            throw CLIError.parseFailure(
                "Could not read this tool's own command tree"
                    + (result.stderr.nilIfBlank.map { ": \($0)" } ?? "")
            )
        }
        return Data(result.stdout.utf8)
    }
}
