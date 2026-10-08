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

    func testNilIfBlankAgreesWithIt() {
        XCTAssertNil("  ".nilIfBlank)
        XCTAssertNil("".nilIfBlank)
        XCTAssertEqual(" a ".nilIfBlank, " a ")
    }

    func testNilIfEmptyCountsWhitespaceAsContent() {
        // The name says empty, and the six copies tools carried meant empty.
        XCTAssertNil("".nilIfEmpty)
        XCTAssertEqual("  ".nilIfEmpty, "  ")
        XCTAssertEqual(" a ".nilIfEmpty, " a ")
    }

    func testAnEmptyArrayIsNil() {
        XCTAssertNil([Int]().nilIfEmpty)
        XCTAssertEqual([1].nilIfEmpty, [1])
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

    private enum PlainError: Error, CustomStringConvertible, CLIErrorConvertible {
        case emptyText
        var description: String { "the text is empty" }
        var cliErrorCode: CLIError.Code { .usage }
    }

    func testADescribedErrorKeepsItsOwnWords() {
        let error = CLIError.wrapping(PlainError.emptyText)
        XCTAssertEqual(error.message, "the text is empty")
        XCTAssertEqual(error.code, .usage)
    }

    func testPrefixedKeepsTheCodeAndHint() {
        let error = CLIError.wrapping(ReaderError.notAnImage, service: "img").prefixed("photo.png")
        XCTAssertEqual(error.message, "photo.png: photo.png contains no image")
        XCTAssertEqual(error.code, .parseFailure)
        XCTAssertEqual(error.hint, "is it really a PNG?")
        XCTAssertEqual(error.service, "img")
    }

    func testAnUnknownErrorStillFallsBackToUpstream() {
        XCTAssertEqual(CLIError.wrapping(UnknownError()).code, .upstream)
    }

    private enum GrantError: Error, CLIErrorDescribing {
        case missing, elsewhere
        var cliError: CLIError {
            switch self {
            case .missing: CLIError(code: .authRequired, message: "no Accessibility grant",
                                    hint: "System Settings > Privacy & Security > Accessibility")
            case .elsewhere: CLIError(code: .notFound, message: "gone", service: "other")
            }
        }
    }

    func testADescribingErrorKeepsItsMessageAndHint() {
        let error = CLIError.wrapping(GrantError.missing, service: "axe")
        XCTAssertEqual(error.code, .authRequired)
        XCTAssertEqual(error.message, "no Accessibility grant")
        XCTAssertEqual(error.hint, "System Settings > Privacy & Security > Accessibility")
        XCTAssertEqual(error.service, "axe", "the command's service fills a blank one")
    }

    func testADescribingErrorKeepsItsOwnService() {
        XCTAssertEqual(CLIError.wrapping(GrantError.elsewhere, service: "axe").service, "other")
    }
}
