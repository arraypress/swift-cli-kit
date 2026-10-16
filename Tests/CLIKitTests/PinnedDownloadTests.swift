//
//  PinnedDownloadTests.swift
//  CLIKit
//
//  What a pinned download trusts: a file is installed only when its digest
//  matches, and nothing is fetched when downloads are off. One live fetch
//  (a 30 KB licence file at a fixed commit) runs only with CLIKIT_LIVE=1.
//

import CryptoKit
import XCTest
@testable import CLIKit

final class PinnedDownloadTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pinned-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func testInstalledOnlyWhenEveryDigestMatches() throws {
        let data = Data("hello".utf8)
        try data.write(to: root.appendingPathComponent("a.txt"))
        let good = PinnedFile(url: URL(string: "https://example.com/a.txt")!, name: "a.txt", sha256: sha(data))
        XCTAssertEqual(PinnedDownload.installed([good], in: root)?.map(\.lastPathComponent), ["a.txt"])
        let bad = PinnedFile(url: good.url, name: "a.txt", sha256: String(repeating: "0", count: 64))
        XCTAssertNil(PinnedDownload.installed([bad], in: root))
        let missing = PinnedFile(url: good.url, name: "b.txt", sha256: sha(data))
        XCTAssertNil(PinnedDownload.installed([good, missing], in: root))
    }

    func testAlreadyInstalledNeedsNoNetworkEvenWhenDownloadsAreOff() async throws {
        let data = Data("x".utf8)
        try data.write(to: root.appendingPathComponent("x.txt"))
        let file = PinnedFile(url: URL(string: "https://invalid.invalid/x.txt")!, name: "x.txt", sha256: sha(data))
        let found = try await PinnedDownload.obtain([file], into: root, label: "x", service: "test", quiet: true,
                                                    environment: [ModelDownloader.disableKey: "1"])
        XCTAssertEqual(found.count, 1)
    }

    func testRefusedWhenDownloadsAreOff() async {
        let file = PinnedFile(url: URL(string: "https://invalid.invalid/y.txt")!, name: "y.txt", sha256: String(repeating: "a", count: 64))
        do {
            _ = try await PinnedDownload.obtain([file], into: root, label: "y", service: "test", quiet: true,
                                                environment: [ModelDownloader.disableKey: "1"])
            XCTFail("fetched with downloads off")
        } catch let error as CLIError {
            XCTAssertEqual(error.code, .notFound)
        } catch { XCTFail("\(error)") }
    }

    func testLiveFetchChecksTheDigest() async throws {
        guard ProcessInfo.processInfo.environment["CLIKIT_LIVE"] == "1" else { throw XCTSkip("set CLIKIT_LIVE=1") }
        let url = URL(string: "https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/bebasneue/OFL.txt")!
        let data = try await URLSession.shared.data(from: url).0
        let file = PinnedFile(url: url, name: "OFL.txt", sha256: sha(data))
        let found = try await PinnedDownload.obtain([file], into: root, label: "licence", service: "test", quiet: true, environment: [:])
        XCTAssertEqual(try Data(contentsOf: found[0]), data)
    }
}
