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

final class CLIErrorConvertibleTests: XCTestCase {

    private enum ReaderError: Error, LocalizedError, CLIErrorConvertible {
        case notAnImage, diskFull

        var errorDescription: String? {
            switch self {
            case .notAnImage: "photo.png contains no image"
            case .diskFull: "the disk is full"
            }
        }

        var cliErrorCode: CLIError.Code {
            switch self {
            case .notAnImage: .parseFailure
            case .diskFull: .upstream
            }
        }

        var cliErrorHint: String? { self == .notAnImage ? "is it really a PNG?" : nil }
    }

    private struct UnknownError: Error {}

    func testAConvertibleErrorNamesItsOwnCode() {
        let error = CLIError.wrapping(ReaderError.notAnImage, service: "img")
        XCTAssertEqual(error.code, .parseFailure)
        XCTAssertEqual(error.code.exitCode.rawValue, 6)
        XCTAssertEqual(error.message, "photo.png contains no image")
        XCTAssertEqual(error.hint, "is it really a PNG?")
        XCTAssertEqual(error.service, "img")
    }

    func testTheHintIsOptional() {
        XCTAssertNil(CLIError.wrapping(ReaderError.diskFull).hint)
    }

    func testAnUnknownErrorStillFallsBackToUpstream() {
        XCTAssertEqual(CLIError.wrapping(UnknownError()).code, .upstream)
    }
}
