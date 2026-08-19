//
//  ToolIndexTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class ToolIndexTests: XCTestCase {

    // MARK: - Fixtures

    private func manifest(
        tool: String,
        summary: String? = "Does a thing.",
        version: String = "1.0.0",
        requiresAuth: Bool = false,
        commands: [Manifest.Command]
    ) -> Manifest {
        Manifest(
            tool: tool, summary: summary, details: nil, version: version,
            service: tool, requiresAuth: requiresAuth,
            formats: ["json", "text"], exitCodes: ["0": "success"],
            commands: commands
        )
    }

    private func command(_ path: [String], summary: String? = nil) -> Manifest.Command {
        Manifest.Command(
            path: path,
            invocation: (["tool"] + path).joined(separator: " "),
            summary: summary,
            details: nil,
            arguments: []
        )
    }

    // MARK: - Merging

    func testDuplicateToolNamesAreIndexedOnceFirstWins() {
        // The same binary reachable by name and by path must not count twice,
        // and which copy survives must not depend on sort internals.
        let index = ToolIndex.build(from: [
            manifest(tool: "dup", version: "1.0.0", commands: [command(["x"])]),
            manifest(tool: "solo", commands: [command(["y"])]),
            manifest(tool: "dup", version: "2.0.0", commands: [command(["x"]), command(["z"])]),
        ])

        XCTAssertEqual(index.toolCount, 2)
        XCTAssertEqual(index.tools.map(\.tool), ["dup", "solo"])
        XCTAssertEqual(index.tools[0].version, "1.0.0", "first occurrence wins")
        XCTAssertEqual(index.commandCount, 2)
    }

    func testToolsAreSortedByNameForStableOutput() {
        // Discovery order varies with the filesystem; an unsorted index would
        // produce a diff on every rebuild.
        let index = ToolIndex.build(from: [
            manifest(tool: "zed", commands: [command(["a"])]),
            manifest(tool: "alpha", commands: [command(["a"])]),
            manifest(tool: "Mid", commands: [command(["a"])]),
        ])
        XCTAssertEqual(index.tools.map(\.tool), ["alpha", "Mid", "zed"])
    }

    func testCountsAggregate() {
        let index = ToolIndex.build(from: [
            manifest(tool: "a", commands: [command([]), command(["x"]), command(["y"])]),
            manifest(tool: "b", commands: [command(["z"])]),
        ])
        XCTAssertEqual(index.toolCount, 2)
        // The root is not invocable work, so it does not count.
        XCTAssertEqual(index.commandCount, 3)
    }

    func testRootCommandIsExcludedFromEntries() {
        let index = ToolIndex.build(from: [
            manifest(tool: "a", commands: [command([], summary: "Root."), command(["run"])])
        ])
        XCTAssertEqual(index.tools[0].commands.map(\.path), [["run"]])
    }

    // MARK: - Summary

    func testSummaryComesFromTheManifestNotASubcommand() {
        // Regression: yt-fetch has no invocable root, so inferring the summary
        // from the first listed command reported it as "Search YouTube."
        let index = ToolIndex.build(from: [
            manifest(
                tool: "yt-fetch",
                summary: "Fetch YouTube metadata.",
                commands: [command(["search"], summary: "Search YouTube.")]
            )
        ])
        XCTAssertEqual(index.tools[0].summary, "Fetch YouTube metadata.")
    }

    func testMissingSummaryStaysNilRatherThanBorrowingOne() {
        let index = ToolIndex.build(from: [
            manifest(tool: "a", summary: nil, commands: [command(["x"], summary: "A subcommand.")])
        ])
        XCTAssertNil(index.tools[0].summary)
    }

    // MARK: - Determinism

    func testTimestampIsOmittedByDefault() {
        // A build that changes nothing must produce a byte-identical file.
        XCTAssertNil(ToolIndex.build(from: [manifest(tool: "a", commands: [])]).generated)
    }

    func testTimestampIsRecordedWhenAsked() {
        let index = ToolIndex.build(
            from: [manifest(tool: "a", commands: [])],
            generated: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(index.generated, "1970-01-01T00:00:00Z")
    }

    func testUnstampedBuildsEncodeIdentically() throws {
        let manifests = [
            manifest(tool: "b", commands: [command(["x"])]),
            manifest(tool: "a", commands: [command(["y"])]),
        ]
        let first = try ToolIndex.build(from: manifests).encoded()
        let second = try ToolIndex.build(from: manifests.reversed()).encoded()
        XCTAssertEqual(first, second, "input order must not change the output")
    }

    // MARK: - Encoding

    func testEncodedIndexIsValidSortedJSON() throws {
        let data = try ToolIndex.build(from: [
            manifest(tool: "a", requiresAuth: true, commands: [command(["x"])])
        ]).encoded()

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["toolCount"] as? Int, 1)

        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(tools[0]["requiresAuth"] as? Bool, true)

        // Sorted keys keep the file diffable.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertLessThan(
            try XCTUnwrap(text.range(of: "\"commandCount\"")).lowerBound,
            try XCTUnwrap(text.range(of: "\"toolCount\"")).lowerBound
        )
    }

    func testIndexRoundTrips() throws {
        let original = ToolIndex.build(from: [manifest(tool: "a", commands: [command(["x"])])])
        let decoded = try JSONDecoder().decode(ToolIndex.self, from: original.encoded())
        XCTAssertEqual(decoded.toolCount, original.toolCount)
        XCTAssertEqual(decoded.tools.first?.tool, "a")
    }

    // MARK: - Edge Cases

    func testEmptyInputProducesAnEmptyIndexNotACrash() {
        let index = ToolIndex.build(from: [])
        XCTAssertEqual(index.toolCount, 0)
        XCTAssertEqual(index.commandCount, 0)
        XCTAssertTrue(index.tools.isEmpty)
    }

    func testToolWithNoInvocableCommandsIsStillListed() {
        // A pure dispatcher is worth knowing exists, even with nothing to run.
        let index = ToolIndex.build(from: [manifest(tool: "a", commands: [command([])])])
        XCTAssertEqual(index.toolCount, 1)
        XCTAssertEqual(index.tools[0].commandCount, 0)
    }

    func testTextRenderingListsEveryToolAndFlagsCredentials() {
        let rendered = ToolIndex.build(from: [
            manifest(tool: "open", commands: [command(["x"])]),
            manifest(tool: "gated", requiresAuth: true, commands: [command(["y"])]),
        ]).renderText()

        XCTAssertTrue(rendered.contains("2 tools"))
        XCTAssertTrue(rendered.contains("open"))
        XCTAssertTrue(rendered.contains("[needs credentials]"))
        // Only the gated one is marked.
        XCTAssertEqual(rendered.components(separatedBy: "[needs credentials]").count - 1, 1)
    }
}
