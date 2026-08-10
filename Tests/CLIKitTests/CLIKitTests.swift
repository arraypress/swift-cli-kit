//
//  CLIKitTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class CLIKitTests: XCTestCase {

    // MARK: - Exit Codes

    func testEveryErrorCodeMapsToADistinctExitCode() {
        let codes = CLIError.Code.allCases.map(\.exitCode.rawValue)
        XCTAssertEqual(Set(codes).count, codes.count, "Exit codes must be unambiguous")
        XCTAssertFalse(codes.contains(CLIExitCode.ok.rawValue), "No failure may exit 0")
    }

    func testExitCodeNumbersAreStable() {
        // These are a public contract. Changing one silently breaks every
        // caller that branches on $?.
        XCTAssertEqual(CLIExitCode.ok.rawValue, 0)
        XCTAssertEqual(CLIExitCode.notFound.rawValue, 1)
        XCTAssertEqual(CLIExitCode.usage.rawValue, 2)
        XCTAssertEqual(CLIExitCode.authRequired.rawValue, 3)
        XCTAssertEqual(CLIExitCode.rateLimited.rawValue, 4)
        XCTAssertEqual(CLIExitCode.upstream.rawValue, 5)
        XCTAssertEqual(CLIExitCode.parseFailure.rawValue, 6)
    }

    // MARK: - Error Envelope

    func testJSONEnvelopeIsValidJSON() throws {
        let error = CLIError.authRequired(
            "TMDB API key not found",
            service: "tmdb",
            hint: "run: tmdb-meta auth login"
        )

        let data = Data(error.jsonEnvelope.utf8)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let payload = try XCTUnwrap(parsed["error"] as? [String: Any])

        XCTAssertEqual(payload["code"] as? String, "auth_required")
        XCTAssertEqual(payload["service"] as? String, "tmdb")
        XCTAssertEqual(payload["hint"] as? String, "run: tmdb-meta auth login")
    }

    func testJSONEnvelopeEscapesControlCharactersAndQuotes() throws {
        let error = CLIError.upstream("said \"no\"\nand\tstopped\\here")
        let data = Data(error.jsonEnvelope.utf8)

        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let payload = try XCTUnwrap(parsed["error"] as? [String: Any])
        XCTAssertEqual(payload["message"] as? String, "said \"no\"\nand\tstopped\\here")
    }

    func testEnvelopeOmitsAbsentOptionalFields() throws {
        let error = CLIError.usage("bad flag")
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(error.jsonEnvelope.utf8)) as? [String: Any]
        )
        let payload = try XCTUnwrap(parsed["error"] as? [String: Any])
        XCTAssertNil(payload["service"])
        XCTAssertNil(payload["hint"])
    }

    // MARK: - Error Mapping

    func testURLErrorsMapToUpstream() {
        let timeout = CLIError.wrapping(URLError(.timedOut), service: "youtube")
        XCTAssertEqual(timeout.code, .upstream)
        XCTAssertEqual(timeout.service, "youtube")

        let offline = CLIError.wrapping(URLError(.notConnectedToInternet))
        XCTAssertEqual(offline.code, .upstream)
    }

    func testWrappingPreservesAnExistingCLIError() {
        let original = CLIError.notFound("no such video", service: "youtube")
        let wrapped = CLIError.wrapping(original, service: "somethingelse")
        XCTAssertEqual(wrapped.code, .notFound)
        XCTAssertEqual(wrapped.service, "youtube", "Must not relabel an error it did not create")
    }

    // MARK: - Masking

    func testMaskRevealsOnlyTheTailOfLongSecrets() {
        XCTAssertEqual(CredentialResolver.mask("abcdefghijklmnop"), "••••mnop")
    }

    func testMaskFullyHidesShortSecrets() {
        // Revealing four of eight characters would give away half the secret.
        XCTAssertFalse(CredentialResolver.mask("shortkey").contains("key"))
        XCTAssertEqual(CredentialResolver.mask("shortkey"), "••••••••")
    }

    // MARK: - Cache Keys

    func testDigestIsStableAndFixedWidth() {
        let first = DiskCache.digest("youtube/transcript/dQw4w9WgXcQ/en")
        let second = DiskCache.digest("youtube/transcript/dQw4w9WgXcQ/en")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 16)
    }

    func testDigestSeparatesNearIdenticalKeys() {
        XCTAssertNotEqual(DiskCache.digest("video/en"), DiskCache.digest("video/es"))
    }

    func testDisabledCacheAlwaysMisses() {
        let cache = DiskCache(tool: "clikit-tests", isEnabled: false)
        cache.store(Data("payload".utf8), for: "key")
        XCTAssertNil(cache.data(for: "key", ttl: 3600))
    }

    func testCacheRoundTripAndExpiry() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clikit-cache-\(UUID().uuidString)")
        setenv("XDG_CACHE_HOME", root.path, 1)
        defer {
            unsetenv("XDG_CACHE_HOME")
            try? FileManager.default.removeItem(at: root)
        }

        let cache = DiskCache(tool: "clikit-tests")
        cache.store(Data("payload".utf8), for: "key")

        XCTAssertEqual(cache.data(for: "key", ttl: 3600), Data("payload".utf8))
        XCTAssertNil(cache.data(for: "key", ttl: 0), "A zero TTL must never hit")
        XCTAssertNil(cache.data(for: "absent", ttl: 3600))
    }

    // MARK: - Credential Store

    private func withTemporaryConfig(_ body: (FileCredentialStore) throws -> Void) rethrows {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clikit-config-\(UUID().uuidString)")
        setenv("XDG_CONFIG_HOME", root.path, 1)
        defer {
            unsetenv("XDG_CONFIG_HOME")
            try? FileManager.default.removeItem(at: root)
        }
        try body(FileCredentialStore(warnsOnLoosePermissions: false))
    }

    func testCredentialRoundTrip() throws {
        try withTemporaryConfig { store in
            XCTAssertNil(try store.read(service: "tmdb", key: "api_key"))

            try store.write(service: "tmdb", key: "api_key", value: "secret-value")
            XCTAssertEqual(try store.read(service: "tmdb", key: "api_key"), "secret-value")

            try store.delete(service: "tmdb", key: "api_key")
            XCTAssertNil(try store.read(service: "tmdb", key: "api_key"))
        }
    }

    func testStoreIsSharedAcrossServices() throws {
        try withTemporaryConfig { store in
            try store.write(service: "tmdb", key: "api_key", value: "a")
            try store.write(service: "discogs", key: "token", value: "b")

            // The point of one shared file: any tool can see every service.
            XCTAssertEqual(try store.storedServices(), ["discogs", "tmdb"])
            XCTAssertEqual(try store.read(service: "discogs", key: "token"), "b")
        }
    }

    func testCredentialsFileIsWrittenAtMode600() throws {
        try withTemporaryConfig { store in
            try store.write(service: "tmdb", key: "api_key", value: "secret")

            let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
            let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).uint16Value
            XCTAssertEqual(mode & 0o777, 0o600, "Secrets must not be group or world readable")
        }
    }

    func testOverwritingACredentialKeepsMode600() throws {
        try withTemporaryConfig { store in
            try store.write(service: "tmdb", key: "api_key", value: "first")
            try store.write(service: "tmdb", key: "api_key", value: "second")

            XCTAssertEqual(try store.read(service: "tmdb", key: "api_key"), "second")
            let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
            let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).uint16Value
            XCTAssertEqual(mode & 0o777, 0o600, "replaceItemAt must not restore looser attributes")
        }
    }

    func testDeleteAllRemovesOnlyTheNamedService() throws {
        try withTemporaryConfig { store in
            try store.write(service: "tmdb", key: "api_key", value: "a")
            try store.write(service: "discogs", key: "token", value: "b")

            try store.deleteAll(service: "tmdb")
            XCTAssertEqual(try store.storedServices(), ["discogs"])
        }
    }

    func testMalformedCredentialsFileIsRefusedNotOverwritten() throws {
        try withTemporaryConfig { store in
            try FileManager.default.createDirectory(
                at: store.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{ not json".utf8).write(to: store.fileURL)

            // Silently starting fresh would destroy secrets recorded nowhere else.
            XCTAssertThrowsError(try store.read(service: "tmdb", key: "api_key")) { error in
                XCTAssertEqual((error as? CLIError)?.code, .usage)
            }
        }
    }

    // MARK: - Resolution Precedence

    private var tmdbSpec: ServiceSpec {
        ServiceSpec(
            id: "tmdb",
            displayName: "TMDB",
            toolName: "tmdb-meta",
            credentials: [
                CredentialSpec(key: "api_key", label: "API key", envNames: ["CLIKIT_TEST_TMDB_KEY"])
            ],
            signupURL: "https://www.themoviedb.org/settings/api"
        )
    }

    func testEnvironmentBeatsStore() throws {
        try withTemporaryConfig { store in
            try store.write(service: "tmdb", key: "api_key", value: "from-store")
            setenv("CLIKIT_TEST_TMDB_KEY", "from-env", 1)
            defer { unsetenv("CLIKIT_TEST_TMDB_KEY") }

            let resolver = CredentialResolver(service: tmdbSpec, store: store)
            XCTAssertEqual(try resolver.resolve("api_key"), "from-env")
        }
    }

    func testStoreIsUsedWhenEnvironmentIsUnset() throws {
        try withTemporaryConfig { store in
            unsetenv("CLIKIT_TEST_TMDB_KEY")
            try store.write(service: "tmdb", key: "api_key", value: "from-store")

            let resolver = CredentialResolver(service: tmdbSpec, store: store)
            XCTAssertEqual(try resolver.resolve("api_key"), "from-store")
        }
    }

    func testEmptyEnvironmentVariableFallsThroughToStore() throws {
        try withTemporaryConfig { store in
            setenv("CLIKIT_TEST_TMDB_KEY", "", 1)
            defer { unsetenv("CLIKIT_TEST_TMDB_KEY") }
            try store.write(service: "tmdb", key: "api_key", value: "from-store")

            let resolver = CredentialResolver(service: tmdbSpec, store: store)
            XCTAssertEqual(try resolver.resolve("api_key"), "from-store")
        }
    }

    func testRequireThrowsAnActionableHint() throws {
        try withTemporaryConfig { store in
            unsetenv("CLIKIT_TEST_TMDB_KEY")
            let resolver = CredentialResolver(service: tmdbSpec, store: store)

            XCTAssertThrowsError(try resolver.require("api_key")) { error in
                guard let cliError = error as? CLIError else { return XCTFail("Wrong error type") }
                XCTAssertEqual(cliError.code, .authRequired)
                XCTAssertEqual(cliError.code.exitCode, .authRequired)

                // The hint is the whole point: a caller must be able to fix this
                // without a human reading prose.
                let hint = cliError.hint ?? ""
                XCTAssertTrue(hint.contains("tmdb-meta auth login"), "Missing repair command: \(hint)")
                XCTAssertTrue(hint.contains("CLIKIT_TEST_TMDB_KEY"), "Missing env var name: \(hint)")
            }
        }
    }

    func testStatusReportsSourceAndNeverLeaksTheSecret() throws {
        try withTemporaryConfig { store in
            unsetenv("CLIKIT_TEST_TMDB_KEY")
            try store.write(service: "tmdb", key: "api_key", value: "super-secret-value")

            let resolver = CredentialResolver(service: tmdbSpec, store: store)
            let statuses = try resolver.statuses()

            XCTAssertEqual(statuses.count, 1)
            XCTAssertEqual(statuses[0].source, .store)
            XCTAssertEqual(statuses[0].preview, "••••alue")
            XCTAssertFalse(statuses[0].preview?.contains("super") ?? false)
        }
    }

    func testAnonymousServicesAreAlwaysReady() {
        let report = AuthStatusReport(
            service: "youtube",
            displayName: "YouTube",
            anonymous: true,
            storeLocation: "/dev/null",
            credentials: []
        )
        XCTAssertTrue(report.ready)
    }

    func testReportIsNotReadyWhenARequiredCredentialIsMissing() {
        let report = AuthStatusReport(
            service: "tmdb",
            displayName: "TMDB",
            anonymous: false,
            storeLocation: "/dev/null",
            credentials: [
                CredentialStatus(
                    key: "api_key", label: "API key", isRequired: true,
                    source: .missing, envName: nil, preview: nil
                )
            ]
        )
        XCTAssertFalse(report.ready)
    }

    func testOptionalCredentialsDoNotBlockReadiness() {
        // An unauthenticated GitHub request works; it just gets a lower limit.
        let report = AuthStatusReport(
            service: "github",
            displayName: "GitHub",
            anonymous: false,
            storeLocation: "/dev/null",
            credentials: [
                CredentialStatus(
                    key: "token", label: "token", isRequired: false,
                    source: .missing, envName: nil, preview: nil
                )
            ]
        )
        XCTAssertTrue(report.ready)
    }

    // MARK: - Cache versioning

    func testUpgradingInvalidatesCachedPayloads() throws {
        // Entries hold rendered payloads, not raw responses. A release that
        // corrects a field would otherwise keep serving the old shape until
        // the TTL expired — a week, for a tool that caches bibliographic data.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clikit-cache-\(UUID().uuidString)")
        setenv("XDG_CACHE_HOME", directory.path, 1)
        defer {
            unsetenv("XDG_CACHE_HOME")
            try? FileManager.default.removeItem(at: directory)
        }

        let old = DiskCache(tool: "test", version: "0.1.0")
        old.store(Data("old payload".utf8), for: "same/key")
        XCTAssertNotNil(old.data(for: "same/key", ttl: 3_600))

        let new = DiskCache(tool: "test", version: "0.2.0")
        XCTAssertNil(new.data(for: "same/key", ttl: 3_600), "a new version must not read the old entry")

        // The old generation is still visible to clear and to the size report.
        XCTAssertGreaterThan(old.usage().entries, 0)
    }

    func testSameVersionStillHits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clikit-cache-\(UUID().uuidString)")
        setenv("XDG_CACHE_HOME", directory.path, 1)
        defer {
            unsetenv("XDG_CACHE_HOME")
            try? FileManager.default.removeItem(at: directory)
        }

        let cache = DiskCache(tool: "test", version: "1.0.0")
        cache.store(Data("payload".utf8), for: "k")
        XCTAssertEqual(
            DiskCache(tool: "test", version: "1.0.0").data(for: "k", ttl: 3_600),
            Data("payload".utf8)
        )
    }
}
