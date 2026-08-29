//
//  SecureFileTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The properties are the security ones: the mode bits on the file and on
//  the directory it made, and that the file is whole after a replacement.
//  Runs against the real filesystem, because only the filesystem can attest
//  to a mode bit.
//

import XCTest
@testable import CLIKit

final class SecureFileTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clikit-secure-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)).intValue
    }

    func testTheFileAndItsNewDirectoryAreOwnerOnly() throws {
        let file = root.appendingPathComponent("nested/profile.json")

        try SecureFile.write(Data("{}".utf8), to: file)

        XCTAssertEqual(try mode(of: file), 0o600)
        XCTAssertEqual(try mode(of: file.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try mode(of: root), 0o700, "the intermediate directory too")
        XCTAssertEqual(try Data(contentsOf: file), Data("{}".utf8))
    }

    func testAReplacementStaysOwnerOnly() throws {
        let file = root.appendingPathComponent("profile.json")
        try SecureFile.write(Data("one".utf8), to: file)
        // Somebody loosened it by hand; the next save must not inherit that.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        try SecureFile.write(Data("two".utf8), to: file)

        XCTAssertEqual(try mode(of: file), 0o600)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "two")
    }

    func testNoTemporaryFileIsLeftBehind() throws {
        let file = root.appendingPathComponent("profile.json")
        try SecureFile.write(Data("one".utf8), to: file)
        try SecureFile.write(Data("two".utf8), to: file)

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names, ["profile.json"])
    }

    func testAnExistingDirectoryIsLeftAtItsOwnMode() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])

        try SecureFile.write(Data("x".utf8), to: root.appendingPathComponent("a.json"))

        XCTAssertEqual(try mode(of: root), 0o755, "the caller's directory is the caller's")
    }

    func testAValueIsWrittenReadably() throws {
        struct Profile: Codable, Equatable { let name: String; let email: String; let site: String }
        let file = root.appendingPathComponent("profile.json")
        let profile = Profile(name: "Alex", email: "alex@moreau.dev", site: "https://alexmoreau.dev")

        try SecureFile.write(profile, to: file)

        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("\n"), "pretty-printed, one key per line")
        XCTAssertTrue(text.contains("https://alexmoreau.dev"), "slashes are not escaped: \(text)")
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "email")).lowerBound,
                          try XCTUnwrap(text.range(of: "name")).lowerBound, "sorted keys")
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: Data(contentsOf: file)), profile)
        XCTAssertEqual(try mode(of: file), 0o600)
    }

    func testAnUnwritablePlaceIsAnUpstreamError() throws {
        let file = URL(fileURLWithPath: "/dev/null/impossible/profile.json")

        XCTAssertThrowsError(try SecureFile.write(Data("x".utf8), to: file)) { error in
            XCTAssertEqual((error as? CLIError)?.code, .upstream)
            XCTAssertTrue(error.cliMessage.contains("Could not"), error.cliMessage)
        }
    }
}
