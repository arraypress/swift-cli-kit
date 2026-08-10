//
//  FieldSelectionTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest

@testable import CLIKit

final class FieldSelectionTests: XCTestCase {

    private struct Video: Codable, TextRenderable {
        let title: String
        let author: String
        let viewCount: Int
        func renderText() -> String { title }
    }

    private let sample = Video(title: "Never Gonna Give You Up", author: "Rick Astley", viewCount: 1_600_000_000)

    /// Captures whatever the emitter writes to stdout.
    private func emitted(fields: [String]?) throws -> [String: Any] {
        let pipe = Pipe()
        let saved = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        try Emitter(format: .json, fields: fields, pretty: false, quiet: true).emit(sample)

        fflush(stdout)
        dup2(saved, STDOUT_FILENO)
        close(saved)
        try pipe.fileHandleForWriting.close()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Comma handling

    func testCommaSeparatedFieldsAreSplit() throws {
        // The trap this fixes: `--fields` parses up to the next option, so
        // `--fields title,author` arrived as one name matching nothing and
        // produced `{}` with exit 0 — a mistake dressed as an answer.
        let object = try emitted(fields: ["title,author"])
        XCTAssertEqual(Set(object.keys), ["title", "author"])
    }

    func testSpaceSeparatedFieldsStillWork() throws {
        let object = try emitted(fields: ["title", "author"])
        XCTAssertEqual(Set(object.keys), ["title", "author"])
    }

    func testMixedAndPaddedFormsAreAccepted() throws {
        let object = try emitted(fields: [" title , author ", "viewCount"])
        XCTAssertEqual(Set(object.keys), ["title", "author", "viewCount"])
    }

    func testEmptyEntriesAreDropped() throws {
        // A trailing comma is a typo, not a request for a field named "".
        let object = try emitted(fields: ["title,,"])
        XCTAssertEqual(Set(object.keys), ["title"])
    }

    func testNormalisationHappensOnce() {
        XCTAssertEqual(
            Emitter(format: .json, fields: ["a,b", " c "]).fields,
            ["a", "b", "c"]
        )
    }

    // MARK: Unknown names

    func testUnknownNamesAreIgnoredAlongsideKnownOnes() throws {
        // Deliberate: a caller narrowing across several services should not
        // have to know which fields each one exposes.
        let object = try emitted(fields: ["title", "nonexistent"])
        XCTAssertEqual(Set(object.keys), ["title"])
    }

    func testEverythingUnknownYieldsAnEmptyObject() throws {
        let object = try emitted(fields: ["nope", "alsoNope"])
        XCTAssertTrue(object.isEmpty)
    }

    func testNoFieldsMeansNoFiltering() throws {
        let object = try emitted(fields: nil)
        XCTAssertEqual(Set(object.keys), ["title", "author", "viewCount"])
    }
}
