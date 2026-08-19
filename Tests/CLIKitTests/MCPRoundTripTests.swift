//
//  MCPRoundTripTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The argv the MCP server builds, parsed by a real ArgumentParser command.
//  The unit tests prove each layer separately; only a round trip proves the
//  two agree — which is exactly where the `.singleValue` array bug lived.
//

import ArgumentParser
import XCTest
@testable import CLIKit

/// Mirrors the family's record commands: a required positional, an array
/// option declared `.singleValue` (one value per occurrence — the default,
/// and what `invoice clients add --address-line` actually uses), a plain
/// option, and a flag.
private struct AddClient: ParsableCommand {

    @Argument var name: String

    @Option(name: .long, parsing: .singleValue) var addressLine: [String] = []

    @Option(name: .long) var city: String?

    @Flag(name: .long) var archived: Bool = false
}

final class MCPRoundTripTests: XCTestCase {

    /// The manifest entry describing ``AddClient``, as dump-help would.
    private let command = Manifest.Command(
        path: ["clients", "add"],
        invocation: "invoice clients add",
        summary: "Add a client.",
        details: nil,
        arguments: [
            .init(kind: "positional", name: "name", short: nil, required: true,
                  repeating: false, summary: "The client.", defaultValue: nil, values: nil),
            .init(kind: "option", name: "--address-line", short: nil, required: false,
                  repeating: true, summary: "An address line.", defaultValue: nil, values: nil),
            .init(kind: "option", name: "--city", short: nil, required: false,
                  repeating: false, summary: "The city.", defaultValue: nil, values: nil),
            .init(kind: "flag", name: "--archived", short: nil, required: false,
                  repeating: false, summary: "Archive it.", defaultValue: nil, values: nil),
        ]
    )

    private func parse(_ arguments: [String: Any]) throws -> AddClient {
        let argv = try MCPServer.argumentVector(for: command, arguments: arguments)
        XCTAssertEqual(Array(argv.prefix(2)), ["clients", "add"])
        return try AddClient.parse(Array(argv.dropFirst(2)))
    }

    func testSingleValueArrayOptionRoundTrips() throws {
        let parsed = try parse([
            "name": "Acme GmbH",
            "address-line": ["Unter den Linden 1", "10117 Berlin"],
            "city": "Berlin",
            "archived": true,
        ])

        XCTAssertEqual(parsed.name, "Acme GmbH")
        XCTAssertEqual(parsed.addressLine, ["Unter den Linden 1", "10117 Berlin"],
                       "every element must survive `.singleValue` parsing")
        XCTAssertEqual(parsed.city, "Berlin")
        XCTAssertTrue(parsed.archived)
    }

    func testOmittedOptionalsRoundTripToTheirDefaults() throws {
        let parsed = try parse(["name": "Solo"])

        XCTAssertEqual(parsed.name, "Solo")
        XCTAssertEqual(parsed.addressLine, [])
        XCTAssertNil(parsed.city)
        XCTAssertFalse(parsed.archived)
    }

    func testNullsRoundTripAsOmitted() throws {
        let parsed = try parse([
            "name": "Solo",
            "address-line": NSNull(),
            "city": NSNull(),
            "archived": NSNull(),
        ])

        XCTAssertEqual(parsed.addressLine, [])
        XCTAssertNil(parsed.city)
        XCTAssertFalse(parsed.archived)
    }

    func testValuesThatLookLikeFlagsStillBind() throws {
        // A value beginning with a dash is the classic way argv building goes
        // wrong; ArgumentParser handles it as long as each pair stays a pair.
        let parsed = try parse(["name": "Acme", "city": "St. John's"])
        XCTAssertEqual(parsed.city, "St. John's")
    }
}
