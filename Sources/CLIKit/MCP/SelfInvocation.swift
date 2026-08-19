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
    static func run(_ arguments: [String]) -> MCPServer.CommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // Never the parent's stdin: under MCP that is the protocol channel,
        // and a child that reads it — `auth login`, or `mcp` itself — would
        // consume protocol frames or block on them forever.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return MCPServer.CommandResult(
                stdout: "",
                stderr: "Could not run \(executableURL.path): \(error.localizedDescription)",
                exitCode: CLIExitCode.upstream.rawValue
            )
        }

        // Read before waiting, and drain both pipes concurrently: a command
        // producing more output than a pipe buffer holds would otherwise block
        // forever on write while we block on exit — and a child that fills the
        // stderr pipe before closing stdout would deadlock sequential reads the
        // same way.
        let errBuffer = DrainBuffer()
        let errQueue = DispatchQueue(label: "cli-kit.self-invocation.stderr")
        let errHandle = err.fileHandleForReading
        errQueue.async { errBuffer.data = errHandle.readDataToEndOfFile() }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        errQueue.sync {}
        process.waitUntilExit()

        return MCPServer.CommandResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errBuffer.data, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    /// A byte buffer a background drain fills while this thread reads the other
    /// pipe. The `sync {}` join orders the write before the read.
    private final class DrainBuffer: @unchecked Sendable {
        var data = Data()
    }

    /// Reads the command tree as ArgumentParser's dump-help JSON.
    static func dumpHelp() throws -> Data {
        let result = run(["--experimental-dump-help"])
        guard result.exitCode == 0, !result.stdout.isEmpty else {
            throw CLIError.parseFailure(
                "Could not read this tool's own command tree"
                    + (result.stderr.nilIfEmpty.map { ": \($0)" } ?? "")
            )
        }
        return Data(result.stdout.utf8)
    }
}
