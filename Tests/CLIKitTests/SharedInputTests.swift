//
//  SharedInputTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The helpers 0.8.0 took out of individual tools. Each was written at least
//  twice across the fleet; these are the rules every copy had to agree on.
//

import XCTest
@testable import CLIKit

final class DateInputTests: XCTestCase {

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    func testISODatesAndPartials() throws {
        let day = try DateInput.parse("2026-01-31", calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: day), DateComponents(year: 2026, month: 1, day: 31))
        let month = try DateInput.parse("2026-06", calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: month), DateComponents(month: 6, day: 1))
        let year = try DateInput.parse("2026", calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: year), DateComponents(month: 1, day: 1))
    }

    func testSpansBackFromNow() throws {
        let now = try DateInput.parse("2026-10-08", calendar: calendar)
        let week = try DateInput.parse("7d", now: now, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: week, to: now).day, 7)
        let months = try DateInput.parse("6M", now: now, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month], from: months, to: now).month, 6)
    }

    func testASpanIsAlwaysBackwards() throws {
        let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
        XCTAssertEqual(try DateInput.parse("-7d", now: now, calendar: calendar),
                       try DateInput.parse("7d", now: now, calendar: calendar))
        XCTAssertLessThan(try DateInput.parse("7d", now: now, calendar: calendar), now)
    }

    func testNonsenseIsAUsageError() {
        // Words are refused rather than guessed at: "yesterday" is one a tool
        // could guess, and the next one it could not.
        for bad in ["next tuesday", "yesterday", "2026-02-30", "26-01-01", "2026-01-xx", ""] {
            XCTAssertThrowsError(try DateInput.parse(bad, calendar: calendar), bad) {
                XCTAssertEqual(($0 as? CLIError)?.code, .usage, bad)
            }
        }
    }
}

final class StampAndSizeTests: XCTestCase {

    func testDisplayStampShape() {
        let stamp = Date(timeIntervalSinceReferenceDate: 812_000_000).displayStamp
        XCTAssertNotNil(stamp.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression))
    }

    func testFileSizes() {
        XCTAssertEqual(0.fileSizeText, ByteCountFormatter.string(fromByteCount: 0, countStyle: .file))
        XCTAssertEqual(Int64(21_398).fileSizeText, ByteCountFormatter.string(fromByteCount: 21_398, countStyle: .file))
        XCTAssertEqual(UInt64.max.fileSizeText, ByteCountFormatter.string(fromByteCount: Int64.max, countStyle: .file))
    }
}

final class TerminalInputTests: XCTestCase {

    func testOnePipeNewlineIsDropped() {
        XCTAssertEqual(Terminal.trimmingFinalNewline("hello\n"), "hello")
        XCTAssertEqual(Terminal.trimmingFinalNewline("hello\n\n"), "hello\n")
        XCTAssertEqual(Terminal.trimmingFinalNewline("hello"), "hello")
    }

    func testACRLFEndingKeepsItsLastLetter() {
        XCTAssertEqual(Terminal.trimmingFinalNewline("hello\r\n"), "hello")
    }

    func testConfirmReadsYesAndDefaultsToNo() throws {
        XCTAssertTrue(try Terminal.confirm("Delete?", assumeYes: false, isInteractive: true, read: { "Y" }))
        XCTAssertTrue(try Terminal.confirm("Delete?", assumeYes: false, isInteractive: true, read: { " yes " }))
        XCTAssertFalse(try Terminal.confirm("Delete?", assumeYes: false, isInteractive: true, read: { "" }))
        XCTAssertFalse(try Terminal.confirm("Delete?", assumeYes: false, isInteractive: true, read: { nil }))
    }

    func testConfirmWithoutATerminalRefusesRatherThanHangs() {
        XCTAssertThrowsError(try Terminal.confirm("Delete?", assumeYes: false, isInteractive: false, read: { XCTFail("read"); return "y" })) {
            XCTAssertEqual(($0 as? CLIError)?.code, .usage)
        }
        XCTAssertTrue(try Terminal.confirm("Delete?", assumeYes: true, isInteractive: false, read: { nil }))
    }
}

final class AvailableURLTests: XCTestCase {

    func testNumbersLikeTheFinder() {
        let folder = URL(fileURLWithPath: "/out")
        let taken: Set<String> = ["/out/invoice.pdf", "/out/invoice 2.pdf", "/out/notes"]
        let exists: (String) -> Bool = { taken.contains($0) }
        XCTAssertEqual(Files.availableURL(for: "photo.jpg", in: folder, exists: exists).path, "/out/photo.jpg")
        XCTAssertEqual(Files.availableURL(for: "invoice.pdf", in: folder, exists: exists).path, "/out/invoice 3.pdf")
        XCTAssertEqual(Files.availableURL(for: "notes", in: folder, exists: exists).path, "/out/notes 2")
    }
}
