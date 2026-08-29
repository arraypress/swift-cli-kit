//
//  FilesTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class FilesTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clikit-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Reading

    func testAFileIsReadAsGiven() throws {
        let file = root.appendingPathComponent("spec.json")
        try Data("{}".utf8).write(to: file)

        XCTAssertEqual(try Files.read(file.path), Data("{}".utf8))
    }

    func testAMissingFileIsNotFoundWithTheHintPassedThrough() {
        XCTAssertThrowsError(try Files.read(root.appendingPathComponent("nope.json").path,
                                            service: "resume", hint: "pass a JSON file")) { error in
            let failure = error as? CLIError
            XCTAssertEqual(failure?.code, .notFound)
            XCTAssertEqual(failure?.service, "resume")
            XCTAssertEqual(failure?.hint, "pass a JSON file")
            XCTAssertTrue(failure?.message.contains("nope.json") ?? false, "the path is named")
        }
    }

    func testATildeIsExpandedWhenReading() {
        // Nothing lives at ~/clikit-files-…, so the error names the path as
        // typed while the lookup happened under the real home directory.
        XCTAssertThrowsError(try Files.read("~/clikit-files-\(UUID().uuidString).json")) { error in
            XCTAssertEqual((error as? CLIError)?.code, .notFound)
            XCTAssertTrue(error.cliMessage.contains("~/"), "the message says what was typed")
        }
    }

    // MARK: - Directories

    func testADirectoryIsMadeWithItsParents() throws {
        let made = try Files.ensureDirectory(root.appendingPathComponent("a/b/c").path)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: made.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testAnExistingDirectoryIsFine() throws {
        XCTAssertEqual(try Files.ensureDirectory(root).path, root.path)
    }

    func testADirectoryThatCannotBeMadeIsUpstream() {
        XCTAssertThrowsError(try Files.ensureDirectory("/dev/null/impossible")) { error in
            XCTAssertEqual((error as? CLIError)?.code, .upstream)
            XCTAssertTrue(error.cliMessage.hasPrefix("Could not create /dev/null/impossible"), error.cliMessage)
        }
    }

    // MARK: - Writing

    func testDataIsWrittenWhereItWasSent() throws {
        let file = root.appendingPathComponent("out.pdf")

        let written = try Files.write(Data("%PDF".utf8), to: file.path)

        XCTAssertEqual(written.path, file.path)
        XCTAssertEqual(try Data(contentsOf: file), Data("%PDF".utf8))
    }

    func testAWriteReplacesWhatWasThere() throws {
        let file = root.appendingPathComponent("out.txt")
        try Files.write(Data("one".utf8), to: file)
        try Files.write(Data("two".utf8), to: file)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "two")
    }

    func testAPlaceThatCannotBeWrittenIsUpstream() {
        XCTAssertThrowsError(try Files.write(Data(), to: "/dev/null/impossible/out.pdf")) { error in
            XCTAssertEqual((error as? CLIError)?.code, .upstream)
            XCTAssertTrue(error.cliMessage.hasPrefix("Could not write /dev/null/impossible/out.pdf"), error.cliMessage)
        }
    }
}
