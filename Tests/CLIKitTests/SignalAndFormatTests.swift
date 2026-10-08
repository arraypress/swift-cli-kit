//
//  SignalAndFormatTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import ArgumentParser
import Foundation
import XCTest
@testable import CLIKit

final class NamedFormatTests: XCTestCase {

    func options(_ arguments: [String]) throws -> CommonOptions {
        try CommonOptions.parse(arguments)
    }

    func testNoFlagNamesNothing() throws {
        // The format still resolves (from the terminal); it was just not asked for.
        XCTAssertNil(try options([]).namedFormat)
        XCTAssertFalse(try options([]).namesStructuredFormat)
    }

    func testEveryFormatFlagIsNamed() throws {
        let cases: [(String, OutputFormat)] = [
            ("--json", .json), ("--text", .text), ("--ndjson", .ndjson), ("--csv", .csv),
            ("--tsv", .tsv), ("--markdown", .markdown), ("--html", .html),
        ]
        for (flag, format) in cases {
            XCTAssertEqual(try options([flag]).namedFormat, format, flag)
            XCTAssertEqual(try options([flag]).format, format, flag)
        }
    }

    func testTsvAndHtmlCountAsStructured() throws {
        // The five hand-written copies of this check all missed these two.
        XCTAssertTrue(try options(["--tsv"]).namesStructuredFormat)
        XCTAssertTrue(try options(["--html"]).namesStructuredFormat)
    }

    func testTextIsNamedButNotStructured() throws {
        XCTAssertEqual(try options(["--text"]).namedFormat, .text)
        XCTAssertFalse(try options(["--text"]).namesStructuredFormat)
    }
}

final class InterruptTests: XCTestCase {

    func testATimeoutEndsTheWait() async {
        let ended = await Interrupt.wait(timeout: 0.05)
        XCTAssertEqual(ended, .timedOut)
    }

    func testCtrlCEndsTheWaitInsteadOfTheProcess() async {
        // SIGINT is ignored before the source is armed, so raising it here
        // reaches the dispatch source and never the default handler.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { raise(SIGINT) }
        let ended = await Interrupt.wait(timeout: 5)
        XCTAssertEqual(ended, .interrupted)
    }

    func testTheFirstCtrlCRunsTheHandler() {
        let ran = expectation(description: "handler")
        let armed = Interrupt.onFirst(secondExits: false) { ran.fulfill() }
        // A dispatch source registers asynchronously; a signal raised in the
        // same instant can arrive before it is listening, and is then ignored.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { raise(SIGINT) }
        wait(for: [ran], timeout: 2)
        armed.remove()
        signal(SIGINT, SIG_IGN)  // leave the test process immune, as the waits above do
    }
}
