//
//  TerminalStdinTests.swift
//  CLIKitTests
//
//  Created by David Sherlock on 2026.
//
//  The stdin rule, tested by actually replacing file descriptor 0.
//
//  This matters more than it looks. The obvious implementation — "stdin is
//  not a terminal, therefore read it to EOF" — hangs forever under an agent
//  harness, which runs commands with stdin on /dev/null or an open pty.
//  Both are character devices, neither is a pipe, and neither ever closes.
//  So the rule is "read only a FIFO or a regular file", and these tests
//  pin it.
//

import Foundation
import XCTest
@testable import CLIKit

final class TerminalStdinTests: XCTestCase {

    /// Runs `body` with file descriptor 0 replaced by `url`, then restores it.
    private func withStdin(from url: URL, _ body: () -> Void) throws {
        let saved = dup(0)
        defer {
            dup2(saved, 0)
            close(saved)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        dup2(handle.fileDescriptor, 0)
        body()
    }

    func testARegularFileOnStdinIsRead() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stdin-\(UUID().uuidString).txt")
        try "10.1038/nature12373\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        try withStdin(from: file) {
            XCTAssertTrue(Terminal.hasPipedStdin)
            XCTAssertEqual(Terminal.pipedStdin(), "10.1038/nature12373\n")
        }
    }

    func testAnEmptyRedirectReadsAsNilRatherThanEmptyString() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stdin-\(UUID().uuidString).txt")
        try "".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        try withStdin(from: file) {
            XCTAssertTrue(Terminal.hasPipedStdin, "the file is still a redirect")
            XCTAssertNil(Terminal.pipedStdin(),
                         "nil lets a caller tell 'nothing piped' from 'an empty thing piped'")
        }
    }

    func testACharacterDeviceIsNotReadBecauseItWouldNeverReturn() throws {
        // /dev/null is exactly what an agent harness hands a subprocess.
        try withStdin(from: URL(fileURLWithPath: "/dev/null")) {
            XCTAssertFalse(Terminal.hasPipedStdin,
                           "a character device must not be read to EOF — that hangs forever")
            XCTAssertNil(Terminal.pipedStdin())
        }
    }

    func testAPipeOnStdinIsRead() throws {
        let pipe = Pipe()
        let saved = dup(0)
        defer { dup2(saved, 0); close(saved) }
        dup2(pipe.fileHandleForReading.fileDescriptor, 0)

        pipe.fileHandleForWriting.write(Data("one\ntwo\n".utf8))
        try pipe.fileHandleForWriting.close()

        XCTAssertTrue(Terminal.hasPipedStdin, "a FIFO is the canonical piped case")
        XCTAssertEqual(Terminal.pipedStdin(), "one\ntwo\n")
    }
}
