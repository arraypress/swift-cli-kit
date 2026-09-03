//
//  EmitterTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest

@testable import CLIKit

// MARK: - --fields on a table

private struct Row: Codable, TableRenderable, Sendable {
    let id: String
    let name: String
    let price: String
    static var tableColumns: [String] { ["ID", "NAME", "PRICE"] }
    static var flexibleColumns: [Int] { [1] }
    var tableRow: [String] { [id, name, price] }
    func renderText() -> String { "\(id) \(name) \(price)" }
}

final class TableFieldsTests: XCTestCase {

    private func capturingStdout(_ body: () throws -> Void) rethrows -> String {
        let pipe = Pipe()
        let saved = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        try body()
        fflush(stdout)
        dup2(saved, STDOUT_FILENO)
        close(saved)
        try? pipe.fileHandleForWriting.close()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private let rows = [
        Row(id: "1", name: "widget", price: "19.98"),
        Row(id: "2", name: "gizmo", price: "5.00"),
    ]

    func testTableHonoursFields() throws {
        // The bug: this printed all three columns and said nothing, while the
        // same flag projected correctly under --json.
        let output = try capturingStdout {
            try Emitter(format: .text, fields: ["id", "price"]).emitAll(rows)
        }
        XCTAssertTrue(output.contains("ID"), output)
        XCTAssertTrue(output.contains("PRICE"), output)
        XCTAssertFalse(output.contains("NAME"), output)
        XCTAssertFalse(output.contains("widget"), output)
        XCTAssertTrue(output.contains("19.98"), output)
    }

    func testMatchingIsCaseInsensitive() throws {
        // Headings print upper-case; nobody types them that way.
        let output = try capturingStdout {
            try Emitter(format: .text, fields: ["PRICE"]).emitAll(rows)
        }
        XCTAssertTrue(output.contains("19.98"), output)
        XCTAssertFalse(output.contains("widget"), output)
    }

    func testNoFieldsMeansEveryColumn() throws {
        let output = try capturingStdout {
            try Emitter(format: .text).emitAll(rows)
        }
        XCTAssertTrue(output.contains("NAME"), output)
    }

    func testAMissedNameWarnsAndKeepsTheTable() throws {
        // Emptying the table would be the worse answer: the caller asked for
        // something that is not there, and silence plus no rows reads as "no
        // data" rather than "wrong flag".
        let output = try capturingStdout {
            try Emitter(format: .text, fields: ["nonexistent"]).emitAll(rows)
        }
        XCTAssertTrue(output.contains("NAME"), output)
        XCTAssertTrue(output.contains("widget"), output)
    }

    func testJSONStillFiltersOnTheUnderlyingKeys() throws {
        let output = try capturingStdout {
            try Emitter(format: .json, fields: ["id", "price"]).emitAll(rows)
        }
        XCTAssertTrue(output.contains("\"price\""), output)
        XCTAssertFalse(output.contains("\"name\""), output)
    }
}
