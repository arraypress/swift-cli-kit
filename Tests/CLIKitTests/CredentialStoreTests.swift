//
//  CredentialStoreTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The credential store holds the family's secrets, so the properties under
//  test are the security ones: the mode bits, the refusal to overwrite a
//  file it cannot read, and the masking that keeps values out of output.
//
//  Runs against the real config root under a disposable namespace — the 0600
//  guarantee is a filesystem fact, and only the filesystem can attest to it.
//

import XCTest
@testable import CLIKit

final class CredentialStoreTests: XCTestCase {

    private var store = FileCredentialStore()

    override func setUp() {
        super.setUp()
        store = FileCredentialStore(
            namespace: "clikit-tests-\(UUID().uuidString.prefix(8))",
            warnsOnLoosePermissions: false
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)).intValue
    }

    // MARK: - Round trips

    func testAValueComesBackAsItWentIn() throws {
        try store.write(service: "tmdb", key: "api_key", value: "sk_live_123456")
        XCTAssertEqual(try store.read(service: "tmdb", key: "api_key"), "sk_live_123456")
        XCTAssertNil(try store.read(service: "tmdb", key: "other"))
        XCTAssertNil(try store.read(service: "discogs", key: "api_key"))
    }

    func testServicesShareTheFileWithoutColliding() throws {
        try store.write(service: "tmdb", key: "api_key", value: "one")
        try store.write(service: "discogs", key: "token", value: "two")

        XCTAssertEqual(try store.storedServices(), ["discogs", "tmdb"])
        XCTAssertEqual(try store.read(service: "tmdb", key: "api_key"), "one")
        XCTAssertEqual(try store.read(service: "discogs", key: "token"), "two")
    }

    // MARK: - Permissions

    func testTheFileIsCreatedOwnerOnly() throws {
        try store.write(service: "tmdb", key: "api_key", value: "secret")
        XCTAssertEqual(try mode(of: store.fileURL), 0o600)
    }

    func testReplacingTheFileKeepsItOwnerOnly() throws {
        // The second write goes through replaceItemAt, which can carry the
        // original's attributes — the mode must survive that path too.
        try store.write(service: "tmdb", key: "api_key", value: "first")
        try store.write(service: "tmdb", key: "api_key", value: "second")

        XCTAssertEqual(try mode(of: store.fileURL), 0o600)
        XCTAssertEqual(try store.read(service: "tmdb", key: "api_key"), "second")
    }

    // MARK: - Damage

    func testAMalformedFileRefusesRatherThanStartingFresh() throws {
        // Overwriting a corrupt store would destroy secrets the user may not
        // have recorded anywhere else; the only safe move is to stop.
        try store.write(service: "tmdb", key: "api_key", value: "secret")
        try Data("{not json".utf8).write(to: store.fileURL)

        XCTAssertThrowsError(try store.read(service: "tmdb", key: "api_key")) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage)
        }
        XCTAssertThrowsError(try store.write(service: "tmdb", key: "api_key", value: "new"))
        XCTAssertEqual(String(decoding: try Data(contentsOf: store.fileURL), as: UTF8.self),
                       "{not json", "the damaged file must be left for inspection")
    }

    func testAnEmptyFileIsAnEmptyStoreNotAnError() throws {
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: store.fileURL)

        XCTAssertNil(try store.read(service: "tmdb", key: "api_key"))
        XCTAssertEqual(try store.storedServices(), [])
    }

    // MARK: - Deleting

    func testDeleteRemovesOneKeyAndDeleteAllRemovesTheService() throws {
        try store.write(service: "tmdb", key: "api_key", value: "a")
        try store.write(service: "tmdb", key: "session", value: "b")

        try store.delete(service: "tmdb", key: "session")
        XCTAssertNil(try store.read(service: "tmdb", key: "session"))
        XCTAssertEqual(try store.read(service: "tmdb", key: "api_key"), "a")

        try store.deleteAll(service: "tmdb")
        XCTAssertEqual(try store.storedServices(), [])
    }

    func testDeletingWhatIsAbsentIsNotAnError() throws {
        XCTAssertNoThrow(try store.delete(service: "tmdb", key: "api_key"))
        XCTAssertNoThrow(try store.deleteAll(service: "tmdb"))
    }

    // MARK: - Masking

    func testShortSecretsAreFullyHidden() {
        // Revealing the last four characters of an eight-character secret
        // gives away half of it; below twelve, nothing shows.
        XCTAssertEqual(CredentialResolver.mask(""), "••••••••")
        XCTAssertEqual(CredentialResolver.mask("elevenchars"), "••••••••")
    }

    func testLongSecretsShowOnlyTheirTail() {
        XCTAssertEqual(CredentialResolver.mask("twelve-chars"), "••••hars")
        XCTAssertEqual(CredentialResolver.mask("sk_live_abcdef123456"), "••••3456")
    }

    // MARK: - Piped secrets

    func testPipedSecretsAreTrimmedTheSameOnBothPaths() {
        // `echo "$KEY" |` reaches readSecret when stdin is not a terminal and
        // readPipedSecret under --stdin; a value that works with one spelling
        // and not the other is a bug report. CRLF is the classic case:
        // strippingNewline removes only the \n.
        XCTAssertEqual(SecurePrompt.trimmed("  sk_live_123 \r"), "sk_live_123")
        XCTAssertEqual(SecurePrompt.trimmed("clean"), "clean")
        XCTAssertNil(SecurePrompt.trimmed(nil))
    }

    // MARK: - XDG resolution

    func testAbsoluteXDGPathsAreHonoured() {
        let fallback = URL(fileURLWithPath: "/fallback", isDirectory: true)
        XCTAssertEqual(XDG.directory("/custom/config", or: fallback).path, "/custom/config")
    }

    func testRelativeAndEmptyXDGPathsAreIgnoredPerSpec() {
        // The spec: a relative base-directory path "should be considered
        // invalid and ignored" — honouring one would scatter secrets relative
        // to whatever directory the tool ran from.
        let fallback = URL(fileURLWithPath: "/fallback", isDirectory: true)
        XCTAssertEqual(XDG.directory("relative/config", or: fallback).path, "/fallback")
        XCTAssertEqual(XDG.directory("", or: fallback).path, "/fallback")
        XCTAssertEqual(XDG.directory(nil, or: fallback).path, "/fallback")
    }
}
