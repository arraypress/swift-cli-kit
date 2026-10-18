//
//  OSAScriptTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The shared osascript runner: a hard timeout that kills, both pipes read
//  together, `--` before the values, and every failure classified with a
//  retry verdict. The real osascript runs only scripts that touch no app.
//

import Foundation
import os
import XCTest
@testable import CLIKit

final class OSAScriptTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("clikit-osa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A stand-in for osascript: a shell script with this body.
    private func fake(_ body: String) throws -> URL {
        let url = folder.appendingPathComponent("osascript-\(UUID().uuidString)")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    // MARK: Values

    func testValuesThatLookLikeFlagsStayValues() throws {
        let echo = "on run argv\nreturn (item 1 of argv) & \"|\" & (item 2 of argv) & \"|\" & (count of argv)\nend run"
        XCTAssertEqual(try OSAScript.run(echo, arguments: ["-s x", "-e"]), "-s x|-e|2")
        XCTAssertEqual(OSAScript.commandLine(source: "s", arguments: ["-e"], language: .javaScript),
                       ["-l", "JavaScript", "-e", "s", "--", "-e"])
    }

    func testOnlyTheTrailingNewlineIsTrimmed() throws {
        XCTAssertEqual(try OSAScript.run("return \"a\" & linefeed & \"b\" & linefeed"), "a\nb\n")
    }

    // MARK: Timeout

    func testAHungScriptIsStoppedAtTheLimit() throws {
        let pid = OSAllocatedUnfairLock<Int32>(initialState: 0)
        let start = Date()
        XCTAssertThrowsError(try OSAScript.run("delay 30", timeout: 1, started: { id in pid.withLock { $0 = id } })) {
            let error = $0 as! OSAScriptError
            XCTAssertEqual(error.reason, .timedOut(seconds: 1))
            XCTAssertEqual(error.retry, .mayHaveCompleted, "it had started — it may have acted")
            XCTAssertEqual(error.cliError.code.exitCode.rawValue, 5)
            XCTAssertTrue(error.cliError.message.contains("within 1 s"), error.cliError.message)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 6)
        let child = pid.withLock { $0 }
        XCTAssertGreaterThan(child, 0)
        XCTAssertFalse(isAlive(child), "the script was killed, not abandoned")
    }

    func testAScriptThatIgnoresSIGTERMIsKilled() throws {
        let stubborn = try fake("trap '' TERM\nwhile true; do sleep 0.1; done")
        let pid = OSAllocatedUnfairLock<Int32>(initialState: 0)
        let start = Date()
        XCTAssertThrowsError(try OSAScript.run("x", timeout: 0.5, executable: stubborn,
                                               started: { id in pid.withLock { $0 = id } })) {
            XCTAssertEqual(($0 as! OSAScriptError).reason, .timedOut(seconds: 0.5))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 8, "SIGKILL follows SIGTERM after the grace")
        XCTAssertFalse(isAlive(pid.withLock { $0 }))
    }

    func testTheLimitComesFromTheCallThenTheEnvironment() {
        XCTAssertEqual(OSAScript.resolvedTimeout(nil, environment: [:]), 15)
        XCTAssertEqual(OSAScript.resolvedTimeout(nil, environment: ["CLIKIT_OSASCRIPT_TIMEOUT": "40"]), 40)
        XCTAssertEqual(OSAScript.resolvedTimeout(3, environment: ["CLIKIT_OSASCRIPT_TIMEOUT": "40"]), 3)
        XCTAssertEqual(OSAScript.resolvedTimeout(nil, environment: ["CLIKIT_OSASCRIPT_TIMEOUT": "soon"]), 15)
    }

    // MARK: Pipes

    func testBothPipesAreReadTogether() throws {
        // 256 KB of stderr before a byte of stdout: a reader that drains
        // stdout first waits for ever while the child waits on stderr.
        let noisy = try fake("head -c 262144 /dev/zero | tr '\\\\0' e >&2\nhead -c 262144 /dev/zero | tr '\\\\0' o")
        let output = try OSAScript.run("x", timeout: 10, executable: noisy)
        XCTAssertEqual(output.count, 262_144)
    }

    // MARK: Failures

    func testACompileErrorHasNotStarted() {
        XCTAssertThrowsError(try OSAScript.run("syntax error here (")) {
            let error = $0 as! OSAScriptError
            XCTAssertEqual(error.retry, .notStarted)
            XCTAssertEqual(error.cliError.code, .parseFailure)
        }
    }

    func testARuntimeErrorMayHaveActed() {
        XCTAssertThrowsError(try OSAScript.run("error \"gone\" number -1728")) {
            let error = $0 as! OSAScriptError
            XCTAssertEqual(error.number, -1728)
            XCTAssertEqual(error.retry, .mayHaveCompleted)
            XCTAssertEqual(error.cliError.code, .notFound)
            XCTAssertTrue(error.cliError.message.contains("gone"), error.cliError.message)
        }
        XCTAssertThrowsError(try OSAScript.run("error \"odd\" number -42")) {
            XCTAssertEqual(($0 as! OSAScriptError).cliError.code, .upstream)
        }
    }

    func testAMissingExecutableHasNotStarted() {
        XCTAssertThrowsError(try OSAScript.run("x", executable: folder.appendingPathComponent("nope"))) {
            let error = $0 as! OSAScriptError
            XCTAssertEqual(error.retry, .notStarted)
            XCTAssertEqual(error.cliError.code, .upstream)
        }
    }

    func testClassification() {
        func classify(_ stderr: String, status: Int32 = 1, signalled: Bool = false) -> OSAScriptError? {
            OSAScriptError.classify(ChildOutput(status: status, signalled: signalled, stderr: Data(stderr.utf8)), timeout: 15)
        }
        XCTAssertNil(classify("", status: 0))

        let denied = classify("execution error: Not authorized to send Apple events to Messages. (-1743)")
        XCTAssertEqual(denied?.cliError.code.exitCode.rawValue, 3)
        XCTAssertEqual(denied?.retry, .notStarted)
        XCTAssertTrue(denied?.cliError.hint?.contains("Automation") == true)

        XCTAssertEqual(classify("execution error: Messages got an error: Application isn’t running. (-600)")?.retry,
                       .notStarted)
        XCTAssertEqual(classify("execution error: AppleEvent timed out. (-1712)")?.retry, .mayHaveCompleted)
        let unnumbered = classify("0:5: syntax error: Expected end of line but found identifier.")
        XCTAssertEqual(unnumbered?.retry, .notStarted, "a syntax error never ran, numbered or not")
        XCTAssertEqual(unnumbered?.cliError.code, .parseFailure)
        XCTAssertEqual(classify("", status: 15, signalled: true)?.retry, .mayHaveCompleted)
        XCTAssertNil(OSAScriptError.errorNumber(in: "no number (here) at all"))
        XCTAssertEqual(OSAScriptError.errorNumber(in: "x (-2741)\n"), -2741, "trailing whitespace is allowed")
        XCTAssertEqual(OSAScriptError.errorNumber(in: "x (-2741)"), -2741)
    }
}
