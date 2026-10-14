//
//  ChildProcessTests.swift
//  CLIKitTests
//
//  Created by David Sherlock on 2026.
//
//  The volume tests are the point: each writes more than a megabyte to BOTH
//  streams, which deadlocks every hand-written reader in the fleet that
//  waits before reading or reads stdout to its end before stderr. A stall
//  shows up as the timeout firing (`timedOut`), never as a hung test run.
//

import Foundation
import os
import XCTest
@testable import CLIKit

/// Collects lines from a background queue.
private final class Lines: Sendable {
    private let lines = OSAllocatedUnfairLock(initialState: [String]())
    func append(_ line: String) { lines.withLock { $0.append(line) } }
    var all: [String] { lines.withLock { $0 } }
}

final class ChildProcessTests: XCTestCase {

    /// Lines per stream in the volume tests: 20,000 × 72 bytes ≈ 1.4 MB each.
    let count = 20_000

    /// A 64-character filler, so a line is "out 00042 " + filler + "\n".
    let filler = String(repeating: "x", count: 61)

    /// Writes `count` numbered lines to stdout and stderr, alternating —
    /// `printf` is a builtin, so no fork per line.
    var interleaved: String {
        """
        i=0
        while [ $i -lt \(count) ]; do
          printf 'out %05d %s\\n' $i \(filler)
          printf 'err %05d %s\\n' $i \(filler) >&2
          i=$((i+1))
        done
        """
    }

    func sh(_ script: String, timeout: Double = 60, stdout: ChildCapture = .all, stderr: ChildCapture = .all,
            onStdout: (@Sendable (String) -> Void)? = nil, onStderr: (@Sendable (String) -> Void)? = nil) throws -> ChildOutput {
        try ChildProcess.runBlocking("/bin/sh", ["-c", script], timeout: timeout, stdout: stdout, stderr: stderr,
                                     onStdout: onStdout, onStderr: onStderr)
    }

    // MARK: - Volume: the deadlocks

    func testInterleavedMegabytesOnBothStreamsBlocking() throws {
        let result = try sh(interleaved)
        XCTAssertFalse(result.timedOut, "stalled")
        XCTAssertTrue(result.succeeded)
        let lineBytes = 4 + 6 + filler.count + 1
        XCTAssertEqual(result.stdout.count, count * lineBytes)
        XCTAssertEqual(result.stderr.count, count * lineBytes)
        XCTAssertGreaterThan(result.stdout.count, 1_000_000)
        XCTAssertTrue(result.stdoutText.hasSuffix("out \(String(format: "%05d", count - 1)) \(filler)\n"))
        XCTAssertTrue(result.stderrText.hasPrefix("err 00000 "))
    }

    func testInterleavedMegabytesOnBothStreamsAsync() async throws {
        let result = try await ChildProcess.run("/bin/sh", ["-c", interleaved], timeout: 60)
        XCTAssertFalse(result.timedOut, "stalled")
        XCTAssertEqual(result.stdout.count, result.stderr.count)
        XCTAssertGreaterThan(result.stderr.count, 1_000_000)
    }

    func testStderrFloodBeforeAnyStdout() throws {
        // The sequential-read trap: stdout read to its end first never ends,
        // because the child is blocked writing stderr nobody reads.
        let result = try sh("head -c 2000000 /dev/zero | tr '\\0' e >&2; head -c 2000000 /dev/zero | tr '\\0' o",
                            timeout: 30)
        XCTAssertFalse(result.timedOut, "stalled")
        XCTAssertEqual(result.stderr.count, 2_000_000)
        XCTAssertEqual(result.stdout.count, 2_000_000)
        XCTAssertEqual(Set(result.stdout), [UInt8(ascii: "o")])
    }

    func testStdoutFloodBeforeAnyStderr() throws {
        let result = try sh("head -c 2000000 /dev/zero | tr '\\0' o; head -c 2000000 /dev/zero | tr '\\0' e >&2",
                            timeout: 30)
        XCTAssertFalse(result.timedOut, "stalled")
        XCTAssertEqual(result.stdout.count, 2_000_000)
        XCTAssertEqual(result.stderr.count, 2_000_000)
    }

    func testLineCallbacksSeeEveryLineInOrderOnBothStreams() throws {
        let out = Lines(), err = Lines()
        let result = try sh(interleaved, stdout: .none, stderr: .lastLines(3),
                            onStdout: out.append, onStderr: err.append)
        XCTAssertFalse(result.timedOut, "stalled")
        XCTAssertEqual(out.all.count, count)
        XCTAssertEqual(err.all.count, count)
        for (index, line) in out.all.enumerated() where index % 997 == 0 || index == count - 1 {
            XCTAssertTrue(line.hasPrefix("out \(String(format: "%05d", index)) "), line)
        }
        XCTAssertEqual(result.stdout, Data(), ".none keeps nothing")
        XCTAssertEqual(result.stderrText.split(separator: "\n").map { String($0.prefix(9)) },
                       ["err 19997", "err 19998", "err 19999"])
    }

    func testLargeInputWhileOutputFills() throws {
        // stdin written on this thread would block once `cat`'s stdout fills.
        let input = Data((0..<3_000_000).map { UInt8($0 % 251) })
        let result = try ChildProcess.runBlocking("/bin/cat", input: input, timeout: 30)
        XCTAssertFalse(result.timedOut, "stalled")
        XCTAssertEqual(result.stdout, input)
    }

    // MARK: - Ending

    func testExitStatusIsReportedNotThrown() throws {
        let result = try sh("echo nope >&2; exit 7")
        XCTAssertEqual(result.status, 7)
        XCTAssertFalse(result.signalled)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.stderrText, "nope\n")
    }

    func testTimeoutStopsTheChildAndKeepsWhatArrived() throws {
        let started = Date()
        let result = try sh("echo before; exec sleep 30", timeout: 0.5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.signalled)
        XCTAssertEqual(result.status, SIGTERM)
        XCTAssertEqual(result.stdoutText, "before\n")
    }

    func testAChildIgnoringSIGTERMIsKilled() throws {
        let started = Date()
        let result = try sh("trap '' TERM; echo armed; while :; do sleep 0.1; done", timeout: 0.5)
        XCTAssertLessThan(Date().timeIntervalSince(started), ChildProcess.killGrace + 8)
        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.status, SIGKILL)
    }

    func testCancellingTheTaskStopsTheChild() async throws {
        let started = Date()
        let task = Task { try await ChildProcess.run("/bin/sleep", ["30"]) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled run must throw")
        } catch let error as ChildProcessError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testAGrandchildHoldingThePipeDoesNotHoldTheResult() throws {
        let started = Date()
        let result = try ChildProcess.runBlocking(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "sleep 4 & echo hi"], environment: nil, directory: nil,
            input: nil, timeout: nil, stdout: .all, stderr: .all, started: nil, onStdout: nil, onStderr: nil,
            drainGrace: 0.3
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(result.stdoutText, "hi\n")
        XCTAssertTrue(result.succeeded)
    }

    // MARK: - Setup

    func testMissingExecutableThrows() {
        XCTAssertThrowsError(try ChildProcess.runBlocking("/nonexistent/tool")) { error in
            guard case .couldNotStart(let executable, _) = error as? ChildProcessError else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(executable, "/nonexistent/tool")
        }
    }

    func testEnvironmentAndDirectory() throws {
        let directory = URL(fileURLWithPath: "/private/tmp")
        let result = try ChildProcess.runBlocking("/bin/sh", ["-c", "echo \"$GREETING\"; pwd"],
                                                  environment: ["GREETING": "hello"], directory: directory)
        XCTAssertEqual(result.stdoutText, "hello\n/private/tmp\n")
    }

    func testStdinIsNeverInherited() throws {
        // A child reading stdin gets end-of-file at once, not the parent's stdin.
        let result = try ChildProcess.runBlocking("/bin/cat", timeout: 10)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.stdout, Data())
    }

    func testStartedHandsOverTheRunningProcess() throws {
        let pid = OSAllocatedUnfairLock(initialState: Int32(0))
        _ = try ChildProcess.runBlocking("/usr/bin/true", started: { process in
            pid.withLock { $0 = process.processIdentifier }
        })
        XCTAssertGreaterThan(pid.withLock { $0 }, 0)
    }
}

final class LineSplitterTests: XCTestCase {

    func lines(_ chunks: [String]) -> [String] {
        var splitter = LineSplitter()
        var lines = chunks.flatMap { splitter.feed(Data($0.utf8)) }
        if let last = splitter.finish() { lines.append(last) }
        return lines
    }

    func testEveryLineEnding() {
        XCTAssertEqual(lines(["a\nb\r\nc\rd"]), ["a", "b", "c", "d"])
    }

    func testCRLFSplitAcrossChunksIsOneEnding() {
        XCTAssertEqual(lines(["a\r", "\nb\n"]), ["a", "b"])
    }

    func testProgressRedrawsAreLines() {
        XCTAssertEqual(lines(["10%\r20%\r", "30%\r\n"]), ["10%", "20%", "30%"])
    }

    func testEmptyLinesSurviveAndNoPhantomLastLine() {
        XCTAssertEqual(lines(["a\n\nb\n"]), ["a", "", "b"])
        XCTAssertEqual(lines(["\n"]), [""])
        XCTAssertEqual(lines([]), [])
    }

    func testALineAcrossManyChunks() {
        XCTAssertEqual(lines(["he", "ll", "o\nwor", "ld"]), ["hello", "world"])
    }

    func testAMultibyteCharacterSplitAcrossChunks() {
        let bytes = Array("café ☕\n".utf8)
        var splitter = LineSplitter()
        var found: [String] = []
        for byte in bytes { found += splitter.feed(Data([byte])) }
        XCTAssertEqual(found, ["café ☕"])
        XCTAssertNil(splitter.finish())
    }
}
