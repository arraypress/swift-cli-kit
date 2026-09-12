//
//  ReceiptTests.swift
//  CLIKitTests
//
//  Created by David Sherlock on 2026.
//
//  Receipts, and the plan/apply split that makes --dry-run mean something.
//

import ArgumentParser
import Foundation
import XCTest
@testable import CLIKit

final class ChangeTests: XCTestCase {

    func testEachShapeReadsAsASentence() {
        XCTAssertEqual(Change(.created, subject: "718").summary, "created 718")
        XCTAssertEqual(Change(.deleted, subject: "718", from: "Notes").summary,
                       "deleted 718 (was Notes)")
        XCTAssertEqual(Change(.moved, subject: "718", from: "Notes", to: "Projects").summary,
                       "moved 718: Notes → Projects")
        XCTAssertEqual(Change(.renamed, subject: "718", to: "New").summary, "renamed 718 → New")
    }

    func testItRoundTripsThroughJSON() throws {
        let change = Change(.updated, subject: "/tmp/a.png", from: "1024", to: "2048",
                            detail: ["format": "png"])
        let data = try JSONEncoder().encode(change)
        XCTAssertEqual(try JSONDecoder().decode(Change.self, from: data), change)
    }
}

final class ReceiptTests: XCTestCase {

    private func receipt(_ changes: [Change], planned: Bool = false) -> Receipt {
        Receipt(tool: "notes", action: "delete", planned: planned, changes: changes)
    }

    func testTheTimestampIsSortableText() {
        let at = receipt([]).at
        XCTAssertTrue(at.hasSuffix("Z"))
        XCTAssertEqual(at.count, 20, "ISO 8601 to the second")
    }

    func testCountsTallyByKind() {
        let result = receipt([Change(.deleted, subject: "a"), Change(.deleted, subject: "b"),
                              Change(.unchanged, subject: "c")]).counts
        XCTAssertEqual(result[.deleted], 2)
        XCTAssertEqual(result[.unchanged], 1)
        XCTAssertNil(result[.created])
    }

    func testNothingChangedWhenEverythingWasLeftAlone() {
        // "nothing to do" and "did nothing by mistake" look identical in a log that omits
        // the subjects it considered, so `unchanged` is recorded and then discounted.
        XCTAssertTrue(receipt([]).isEmpty)
        XCTAssertTrue(receipt([Change(.unchanged, subject: "a")]).isEmpty)
        XCTAssertFalse(receipt([Change(.unchanged, subject: "a"), Change(.deleted, subject: "b")]).isEmpty)
    }

    func testAPlanAndAReceiptHaveTheSameShape() throws {
        // So a caller reads one format, and a plan can be diffed against what followed it.
        let planned = try JSONEncoder().encode(ReceiptPayload(receipt([], planned: true)))
        let done = try JSONEncoder().encode(ReceiptPayload(receipt([], planned: false)))
        func keys(_ data: Data) throws -> Set<String> {
            Set((try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]).keys)
        }
        XCTAssertEqual(try keys(planned), try keys(done))
        XCTAssertTrue(try keys(planned).contains("planned"))
    }

    func testTheTextRenderingSaysWhetherItHappened() {
        let change = [Change(.deleted, subject: "718", from: "Notes")]
        XCTAssertEqual(ReceiptPayload(receipt(change, planned: true)).renderText(),
                       "would deleted 718 (was Notes)")
        XCTAssertEqual(ReceiptPayload(receipt(change)).renderText(), "deleted 718 (was Notes)")
        XCTAssertEqual(ReceiptPayload(receipt([], planned: true)).renderText(), "delete: nothing to do")
        XCTAssertEqual(ReceiptPayload(receipt([])).renderText(), "delete: nothing changed")
    }
}

final class WriteOptionsTests: XCTestCase {

    func testDryRunIsOffUnlessAskedFor() throws {
        XCTAssertFalse(try WriteOptions.parse([]).dryRun)
        XCTAssertTrue(try WriteOptions.parse(["--dry-run"]).dryRun)
    }

    func testAReceiptIsWrittenWhereAsked() throws {
        let path = NSTemporaryDirectory() + "receipt-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let options = try WriteOptions.parse(["--receipt", path])
        try options.save(Receipt(tool: "notes", action: "delete", planned: false,
                                 changes: [Change(.deleted, subject: "718")]), service: "notes")

        let decoded = try JSONDecoder().decode(Receipt.self,
                                               from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(decoded.changes.first?.subject, "718")
        XCTAssertEqual(decoded.tool, "notes")
    }

    func testNoReceiptRequestedWritesNothing() throws {
        XCTAssertNoThrow(try WriteOptions.parse([]).save(
            Receipt(tool: "t", action: "a", planned: false, changes: []), service: "t"))
    }

    func testAReceiptThatCannotBeSavedIsAnError() throws {
        // Worse than not asking for one: the caller believes they have a record.
        let options = try WriteOptions.parse(["--receipt", "/nope/nowhere/receipt.json"])
        XCTAssertThrowsError(try options.save(
            Receipt(tool: "t", action: "a", planned: false, changes: []), service: "t"))
    }
}

// MARK: - The plan/apply split

/// Records whether `apply` ran, across a command that ArgumentParser constructs itself.
private final class Ledger: @unchecked Sendable {
    static let shared = Ledger()
    var planned = 0
    var applied = 0
    func reset() { planned = 0; applied = 0 }
}

private struct FakeWrite: MutatingCommand {
    static let serviceID = "fake"
    static let actionName = "burn"

    @OptionGroup var common: CommonOptions
    @OptionGroup var write: WriteOptions

    func plan() async throws -> [Change] {
        Ledger.shared.planned += 1
        return [Change(.deleted, subject: "a"), Change(.unchanged, subject: "b")]
    }

    func apply(_ plan: [Change]) async throws -> [Change] {
        Ledger.shared.applied += 1
        return plan
    }
}

final class MutatingCommandTests: XCTestCase {

    override func setUp() { super.setUp(); Ledger.shared.reset() }

    func testADryRunPlansAndDoesNotApply() async throws {
        // The one promise this protocol makes. A conformer that does the work in plan()
        // breaks --dry-run for every tool, so the flow itself is what gets tested.
        var command = try FakeWrite.parse(["--dry-run", "--quiet"])
        try await command.execute()
        XCTAssertEqual(Ledger.shared.planned, 1)
        XCTAssertEqual(Ledger.shared.applied, 0, "--dry-run applied the change")
    }

    func testARealRunPlansThenApplies() async throws {
        var command = try FakeWrite.parse(["--quiet"])
        try await command.execute()
        XCTAssertEqual(Ledger.shared.planned, 1)
        XCTAssertEqual(Ledger.shared.applied, 1)
    }

    func testTheReceiptOnDiskSaysWhetherItWasOnlyAPlan() async throws {
        let path = NSTemporaryDirectory() + "flow-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        var dry = try FakeWrite.parse(["--dry-run", "--receipt", path, "--quiet"])
        try await dry.execute()
        var receipt = try JSONDecoder().decode(Receipt.self,
                                               from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertTrue(receipt.planned)
        XCTAssertEqual(receipt.action, "burn")
        XCTAssertEqual(receipt.changes.count, 2)

        var real = try FakeWrite.parse(["--receipt", path, "--quiet"])
        try await real.execute()
        receipt = try JSONDecoder().decode(Receipt.self,
                                           from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertFalse(receipt.planned)
    }

    func testAFailedReceiptStopsTheCommandRatherThanReportingSuccess() async throws {
        var command = try FakeWrite.parse(["--receipt", "/nope/nowhere/x.json", "--quiet"])
        do {
            try await command.execute()
            XCTFail("a receipt that could not be written was reported as fine")
        } catch {
            // The change still happened — the receipt is written after apply, because a
            // receipt for something that did not happen would be the worse lie.
            XCTAssertEqual(Ledger.shared.applied, 1)
        }
    }
}
