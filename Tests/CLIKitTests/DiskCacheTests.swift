//
//  DiskCacheTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Exercised against the real cache root under a disposable namespace, torn
//  down after every test — the cache's behaviour *is* its filesystem
//  behaviour, and a mock filesystem would test the mock.
//

import XCTest
@testable import CLIKit

final class DiskCacheTests: XCTestCase {

    private var namespace = ""

    override func setUp() {
        super.setUp()
        namespace = "clikit-tests-\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() {
        let cache = DiskCache(tool: "probe", namespace: namespace, version: "1")
        try? FileManager.default.removeItem(at: cache.directoryURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func cache(version: String = "1", enabled: Bool = true) -> DiskCache {
        DiskCache(tool: "probe", namespace: namespace, isEnabled: enabled, version: version)
    }

    /// The entry files currently on disk, the generation marker excluded.
    private func entries(of cache: DiskCache) -> [URL] {
        let listing = (try? FileManager.default.contentsOfDirectory(
            at: cache.directoryURL, includingPropertiesForKeys: nil
        )) ?? []
        return listing.filter { $0.lastPathComponent != "generation" }
    }

    // MARK: - Reading and writing

    func testStoredDataComesBackWithinItsTTL() {
        let cache = self.cache()
        cache.store(Data("payload".utf8), for: "key")
        XCTAssertEqual(cache.data(for: "key", ttl: 60), Data("payload".utf8))
    }

    func testMissIsNilNotAnError() {
        XCTAssertNil(cache().data(for: "never-written", ttl: 60))
    }

    func testKeysDoNotCollideAcrossValues() {
        let cache = self.cache()
        cache.store(Data("a".utf8), for: "first")
        cache.store(Data("b".utf8), for: "second")
        XCTAssertEqual(cache.data(for: "first", ttl: 60), Data("a".utf8))
        XCTAssertEqual(cache.data(for: "second", ttl: 60), Data("b".utf8))
    }

    // MARK: - Expiry

    func testExpiredEntryIsAMissAndItsFileIsRemoved() throws {
        let cache = self.cache()
        cache.store(Data("stale".utf8), for: "key")

        // Age the entry past the TTL by backdating its mtime — the mtime *is*
        // the cache's notion of age, so this is the real expiry path.
        let entry = try XCTUnwrap(entries(of: cache).first)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -7200)],
            ofItemAtPath: entry.path
        )

        XCTAssertNil(cache.data(for: "key", ttl: 3600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.path),
                       "an expired entry must be swept, not merely skipped")
    }

    func testZeroTTLNeverReads() {
        let cache = self.cache()
        cache.store(Data("x".utf8), for: "key")
        XCTAssertNil(cache.data(for: "key", ttl: 0))
    }

    // MARK: - Disabled

    func testDisabledCacheIsCompletelyInert() {
        let disabled = cache(enabled: false)
        disabled.store(Data("x".utf8), for: "key")

        XCTAssertNil(disabled.data(for: "key", ttl: 60))
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabled.directoryURL.path),
                       "--no-cache must not even create the directory")
    }

    // MARK: - Generations

    func testNewVersionPurgesTheOldGenerationsEntries() {
        let old = cache(version: "1")
        old.store(Data("v1".utf8), for: "key")
        XCTAssertEqual(entries(of: old).count, 1)

        let new = cache(version: "2")
        new.store(Data("v2".utf8), for: "key")

        // The v1 entry can never be read again — its version is baked into
        // the digest — so leaving it would leak one orphan set per upgrade.
        XCTAssertEqual(entries(of: new).count, 1)
        XCTAssertNil(old.data(for: "key", ttl: 60))
        XCTAssertEqual(new.data(for: "key", ttl: 60), Data("v2".utf8))
    }

    func testSameVersionDoesNotPurge() {
        let cache = self.cache()
        cache.store(Data("a".utf8), for: "first")
        cache.store(Data("b".utf8), for: "second")
        XCTAssertEqual(entries(of: cache).count, 2)
    }

    // MARK: - Memoising

    func testCachedProducesOnceAndServesTheCopyAfter() async throws {
        let cache = self.cache()
        var produced = 0

        for _ in 0..<3 {
            let value = try await cache.cached("memo", ttl: 60) {
                produced += 1
                return ["answer": 42]
            }
            XCTAssertEqual(value, ["answer": 42])
        }
        XCTAssertEqual(produced, 1, "repeat lookups must be served from disk")
    }

    func testCachedFallsBackToALiveFetchWhenTheEntryIsCorrupt() async throws {
        let cache = self.cache()
        _ = try await cache.cached("memo", ttl: 60) { ["ok": true] }

        // Corrupt the entry by hand; the next call must fetch, not fail.
        let entry = try XCTUnwrap(entries(of: cache).first)
        try Data("{not json".utf8).write(to: entry)

        let value = try await cache.cached("memo", ttl: 60) { ["ok": false] }
        XCTAssertEqual(value, ["ok": false])
    }

    // MARK: - Maintenance

    func testClearRemovesEverythingAndUsageSaysSo() throws {
        let cache = self.cache()
        cache.store(Data("abc".utf8), for: "key")

        let before = cache.usage()
        XCTAssertEqual(before.entries, 1)
        XCTAssertEqual(before.bytes, 3)

        try cache.clear()
        let after = cache.usage()
        XCTAssertEqual(after.entries, 0)
        XCTAssertEqual(after.bytes, 0)
    }

    // MARK: - Hashing

    func testDigestIsStableAndFilesystemSafe() {
        let digest = DiskCache.digest("v1\u{001F}some key with / and spaces")
        XCTAssertEqual(digest, DiskCache.digest("v1\u{001F}some key with / and spaces"))
        XCTAssertEqual(digest.count, 16)
        XCTAssertTrue(digest.allSatisfy(\.isHexDigit))
    }
}
