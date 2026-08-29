//
//  SmallHelperTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The one-liners: each is here because a tool got it wrong inline.
//

import XCTest
@testable import CLIKit

final class SmallHelperTests: XCTestCase {

    // MARK: - isBlank

    func testBlankIsEmptyOrOnlyWhitespace() {
        XCTAssertTrue("".isBlank)
        XCTAssertTrue("   ".isBlank)
        XCTAssertTrue("\n\t ".isBlank)
        XCTAssertFalse(" a ".isBlank)
    }

    func testNilIfEmptyAgreesWithIt() {
        XCTAssertNil("  ".nilIfEmpty)
        XCTAssertEqual(" a ".nilIfEmpty, " a ")
    }

    // MARK: - counted

    func testOneIsSingularAndTheRestAreNot() {
        XCTAssertEqual("page".counted(1), "1 page")
        XCTAssertEqual("page".counted(3), "3 pages")
        XCTAssertEqual("page".counted(0), "0 pages")
    }

    func testAnIrregularPluralIsGiven() {
        XCTAssertEqual("entry".counted(2, plural: "entries"), "2 entries")
        XCTAssertEqual("entry".counted(1, plural: "entries"), "1 entry")
    }

    // MARK: - cliMessage

    func testACLIErrorReportsItsOwnMessage() {
        let error: Error = CLIError.usage("Unknown design 'ledgerr'", hint: "see: resume designs")
        XCTAssertEqual(error.cliMessage, "Unknown design 'ledgerr'")
    }

    func testAnythingElseReportsItsDescription() {
        let error: Error = NSError(domain: "test", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "the disk is full"])
        XCTAssertEqual(error.cliMessage, "the disk is full")
    }
}
