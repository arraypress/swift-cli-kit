//
//  FileSetTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class FileSetTests: XCTestCase {

    // MARK: - Gathering

    func testAFolderIsWalkedForMatchingFiles() throws {
        let root = try Self.tree()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = try FileSet.gather([root.path], matching: ["txt", "csv"], recursive: false)
        XCTAssertEqual(found.map(\.lastPathComponent), ["a.txt", "b.csv"], "sorted, and the .pdf ignored")
    }

    func testSubFoldersAreOnlyWalkedWhenAsked() throws {
        let root = try Self.tree()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(try FileSet.gather([root.path], matching: ["txt", "csv"]).count, 2)
        XCTAssertEqual(
            try FileSet.gather([root.path], matching: ["txt", "csv"], recursive: true).count, 3
        )
    }

    /// A folder has no extension either, so accepting "" for extensionless
    /// files counted every sub-folder as one.
    func testFoldersAreNotMistakenForExtensionlessFiles() throws {
        let root = try Self.tree()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = try FileSet.gather([root.path], matching: [""], recursive: true)
        XCTAssertEqual(found.map(\.lastPathComponent), ["emails"], "the nested folder is not a file")
    }

    /// The caller named it, so it is read whatever it is called.
    func testAFileNamedOutrightIgnoresTheFilter() throws {
        let root = try Self.tree()
        defer { try? FileManager.default.removeItem(at: root) }

        let odd = root.appendingPathComponent("notes.pdf")
        XCTAssertEqual(try FileSet.gather([odd.path], matching: ["txt"]), [odd])
    }

    /// A typo that quietly matches nothing is worse than a refusal: the run
    /// reports success over an empty set.
    func testAMissingPathIsRefusedRatherThanSkipped() {
        XCTAssertThrowsError(try FileSet.gather(["/no/such/place"], matching: ["txt"]))
    }

    func testTheOrderIsStable() throws {
        let root = try Self.tree()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try FileSet.gather([root.path], matching: ["txt", "csv"], recursive: true)
        let second = try FileSet.gather([root.path], matching: ["txt", "csv"], recursive: true)
        XCTAssertEqual(first, second)
    }

    // MARK: - Reading lists

    func testLineNumbersAreTheOnesInTheFile() throws {
        let file = try Self.list("""
            first@example.com
            second@example.com

            # a comment
            fifth@example.com
            """)
        defer { try? FileManager.default.removeItem(at: file) }

        let values = try ValueList.read(file)
        XCTAssertEqual(values.map(\.text), [
            "first@example.com", "second@example.com", "fifth@example.com",
        ])
        XCTAssertEqual(values.map(\.source), [
            "\(file.lastPathComponent):1",
            "\(file.lastPathComponent):2",
            "\(file.lastPathComponent):5",
        ], "the blank and the comment still occupy their lines")
    }

    func testQuotedFieldsAreUnwrapped() throws {
        let file = try Self.list("\"quoted@example.com\"\nplain@example.org")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(
            try ValueList.read(file).map(\.text),
            ["quoted@example.com", "plain@example.org"]
        )
    }

    func testAFileOfNothingButCommentsReadsAsEmpty() throws {
        let file = try Self.list("\n\n# nothing here\n\n")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(try ValueList.read(file).isEmpty)
    }

    func testSomethingThatIsNotTextIsRefused() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-kit-binary-\(UUID().uuidString).txt")
        try Data([0xFF, 0xFE, 0x00, 0x01, 0xFF]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertThrowsError(try ValueList.read(file))
    }

    // MARK: - Builders

    /// Two matching files, a nested third, an extensionless one, and a .pdf.
    private static func tree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-kit-tree-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        for (url, body) in [
            (root.appendingPathComponent("a.txt"), "a"),
            (root.appendingPathComponent("b.csv"), "b"),
            (root.appendingPathComponent("emails"), "c"),
            (root.appendingPathComponent("notes.pdf"), "d"),
            (nested.appendingPathComponent("c.txt"), "e"),
        ] {
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private static func list(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-kit-list-\(UUID().uuidString).txt")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
