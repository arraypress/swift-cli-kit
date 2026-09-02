//
//  CacheCommandTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The verb twenty-eight tools had each written for themselves, and the
//  papercut every copy shared: `info` declared only --json, so --csv and
//  --text were accepted and ignored.
//

import ArgumentParser
import XCTest
@testable import CLIKit

/// A stand-in tool, so the generic can be instantiated.
private struct FakeCLI: ParsableCommand, ServiceProviding {
    static let service = ServiceSpec(
        id: "faketool", displayName: "Fake", toolName: "faketool", credentials: []
    )
}

final class CacheCommandTests: XCTestCase {

    // MARK: The papercut

    func testInfoHonoursEveryOutputFlagNotJustJSON() throws {
        // The whole reason this moved into CLIKit. Each hand-rolled copy had
        // a lone `@Flag var json`, so `cache info --csv` parsed and then
        // printed JSON anyway.
        for (arguments, expected) in [
            (["--json"], OutputFormat.json),
            (["--csv"], .csv),
            (["--markdown"], .markdown),
            (["--ndjson"], .ndjson),
        ] as [([String], OutputFormat)] {
            let command = try CacheCommand<FakeCLI>.Info.parse(arguments)
            XCTAssertEqual(command.common.format, expected, "\(arguments) should select \(expected)")
        }
    }

    func testInfoTakesTheOtherSharedOptionsToo() throws {
        XCTAssertNoThrow(try CacheCommand<FakeCLI>.Info.parse(["--quiet"]))
        XCTAssertNoThrow(try CacheCommand<FakeCLI>.Info.parse(["--fields", "entries", "bytes"]))
        XCTAssertTrue(try CacheCommand<FakeCLI>.Info.parse(["--full"]).common.full)
    }

    func testClearCanBeQuietened() throws {
        XCTAssertTrue(try CacheCommand<FakeCLI>.Clear.parse(["--quiet"]).common.quiet)
        XCTAssertFalse(try CacheCommand<FakeCLI>.Clear.parse([]).common.quiet)
    }

    // MARK: Shape

    func testInfoIsTheDefaultSoBareCacheReportsRatherThanDeletes() {
        // `cache` on its own must never be destructive.
        XCTAssertEqual(CacheCommand<FakeCLI>.configuration.commandName, "cache")
        XCTAssertTrue(CacheCommand<FakeCLI>.configuration.defaultSubcommand == CacheCommand<FakeCLI>.Info.self)
    }

    func testTheNamespaceComesFromTheToolsOwnServiceSpec() {
        // So it cannot drift from the namespace the tool reads and writes.
        XCTAssertEqual(FakeCLI.service.toolName, "faketool")
        XCTAssertTrue(DiskCache(tool: FakeCLI.service.toolName).directoryURL.path.contains("faketool"))
    }

    // MARK: The report

    func testAnEmptyCacheSaysSoRatherThanPrintingZeroes() {
        let report = CacheReport(location: "/tmp/x", entries: 0, bytes: 0)
        XCTAssertEqual(report.renderText(), "Empty. /tmp/x")
    }

    func testSizeIsFormattedForAPersonAndBytesKeptForAMachine() {
        let report = CacheReport(location: "/tmp/x", entries: 3, bytes: 5_000_000)
        XCTAssertTrue(report.size.contains("MB"), "got \(report.size)")
        XCTAssertEqual(report.bytes, 5_000_000, "the raw count stays in the JSON")
        XCTAssertTrue(report.renderText().contains("3 entries"))
    }

    func testOneEntryIsNotPluralised() {
        XCTAssertTrue(CacheReport(location: "/x", entries: 1, bytes: 10).renderText().contains("1 entry"))
    }
}
