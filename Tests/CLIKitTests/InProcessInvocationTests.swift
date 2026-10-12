//
//  InProcessInvocationTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A warm MCP command runs in the server's process: its stdout must be
//  captured, not written to the protocol channel, and failures must come back
//  as a subprocess's would.
//

import ArgumentParser
import XCTest
@testable import CLIKit

private struct WarmRoot: AsyncParsableCommand, MCPKeepsWarm {
    static let configuration = CommandConfiguration(commandName: "warm", subcommands: [Say.self])
    static let warmCommands: Set<String> = ["say"]

    struct Say: AsyncParsableCommand {
        @Argument var word: String
        @Flag var fail = false
        func run() async throws {
            if fail { throw CLIError.notFound("no \(word)", service: "warm") }
            Terminal.writeLine("said \(word)")
        }
    }
}

final class InProcessInvocationTests: XCTestCase {

    func testCaptureCollectsStandardOutput() async {
        let (value, text) = await Terminal.capturingStandardOutput { () async -> Int in
            Terminal.write("a")
            Terminal.writeLine("b")
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(text, "ab\n")
        XCTAssertFalse(StandardOutputCapture.append(Data("x".utf8)), "the capture closes afterwards")
    }

    func testACommandRunsInProcessLikeASubprocess() async {
        let ok = await InProcessInvocation.outcome(WarmRoot.self, ["say", "hi"])
        XCTAssertEqual(ok.exitCode, 0)
        XCTAssertEqual(ok.stdout, "said hi\n")

        let missing = await InProcessInvocation.outcome(WarmRoot.self, ["say", "hi", "--fail"])
        XCTAssertEqual(missing.exitCode, CLIExitCode.notFound.rawValue)
        XCTAssertTrue(missing.stderr.contains("\"not_found\"") || missing.stderr.contains("no hi"), missing.stderr)

        let usage = await InProcessInvocation.outcome(WarmRoot.self, ["say"])
        XCTAssertEqual(usage.exitCode, CLIExitCode.usage.rawValue)
    }
}
