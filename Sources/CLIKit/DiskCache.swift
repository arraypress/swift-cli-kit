//
//  DiskCache.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A small TTL cache on disk. Repeat lookups are the common case for automated
//  callers, and every one served locally is a request the upstream service does
//  not rate limit us for.
//

import Foundation

/// A time-limited on-disk response cache.
///
/// Scoped per tool under the shared cache root:
///
/// ```
/// ~/.cache/arraypress/yt-meta/3f2a9c1e0b774d55
/// ```
///
/// Deliberately unsophisticated — no index, no eviction thread, no locking.
/// Entries are plain files whose modification time is their age, so the cache
/// can be inspected with `ls` and reset with `rm -rf`. A corrupt or missing
/// entry degrades to a cache miss rather than an error, which keeps the cache
/// off the failure path entirely.
public struct DiskCache: Sendable {

    // MARK: Properties

    /// The tool's own subdirectory name, e.g. `"yt-meta"`.
    public let tool: String

    /// The shared cache namespace.
    public let namespace: String

    /// Whether reads and writes do anything. `--no-cache` sets this false.
    public let isEnabled: Bool

    /// The tool version an entry was written by.
    ///
    /// Mixed into every key so that upgrading invalidates the cache. Entries
    /// hold *rendered payloads*, not raw responses, so a release that changes
    /// a field — a corrected URL, a renamed key, a new default — would
    /// otherwise keep serving the old shape until the TTL expired. On a
    /// week-long TTL that is a week of a fixed bug looking unfixed, and the
    /// user has no reason to suspect the cache.
    public let version: String

    // MARK: Initialisation

    public init(
        tool: String,
        namespace: String = "arraypress",
        isEnabled: Bool = true,
        version: String = DiskCache.callerVersion
    ) {
        self.tool = tool
        self.namespace = namespace
        self.isEnabled = isEnabled
        self.version = version
    }

    /// The running binary's version, read from its bundle.
    ///
    /// Falls back to the executable's modification time, so a locally built
    /// binary still invalidates when rebuilt — during development the version
    /// string rarely changes but the payload shape often does.
    public static let callerVersion: String = {
        if let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !short.isEmpty {
            return short
        }
        let path = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        if let modified = try? FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date {
            return String(Int(modified.timeIntervalSince1970))
        }
        return "0"
    }()

    // MARK: Location

    /// The cache directory, honouring `XDG_CACHE_HOME`.
    public var directoryURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = environment["XDG_CACHE_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache", isDirectory: true)
        }
        return base
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(tool, isDirectory: true)
    }

    private func entryURL(for key: String) -> URL {
        // The version is part of the digested key rather than a directory, so
        // `cache clear` and the size report still see every generation.
        directoryURL.appendingPathComponent(Self.digest("v\(version)\u{001F}\(key)"), isDirectory: false)
    }

    // MARK: Reading

    /// Returns cached data for a key when it exists and is younger than `ttl`.
    ///
    /// - Parameters:
    ///   - key: A stable identifier for the request. Include every input that
    ///     changes the response — endpoint, identifiers, language, page.
    ///   - ttl: The maximum acceptable age in seconds.
    /// - Returns: The cached bytes, or `nil` on any miss, expiry or read error.
    public func data(for key: String, ttl: TimeInterval) -> Data? {
        guard isEnabled, ttl > 0 else { return nil }

        let url = entryURL(for: key)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }

        guard Date().timeIntervalSince(modified) < ttl else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return try? Data(contentsOf: url)
    }

    // MARK: Writing

    /// Caches data under a key. Failures are silent by design.
    ///
    /// A cache write that cannot complete — read-only home, full disk — is not
    /// a reason to fail a request that already succeeded.
    public func store(_ data: Data, for key: String) {
        guard isEnabled else { return }

        let directory = directoryURL
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try? data.write(to: entryURL(for: key), options: .atomic)
    }

    // MARK: Memoising

    /// Returns a cached value, or produces and caches a fresh one.
    ///
    /// The value round-trips through JSON, so what is cached is the tool's own
    /// canonical payload rather than an upstream response. That keeps entries
    /// independent of output format — the same cached object serves `--json`,
    /// `--text` and `--fields`.
    ///
    /// Cache read or write failures degrade to a live fetch. A cache is never a
    /// reason for a command to fail.
    ///
    /// - Parameters:
    ///   - key: A stable identifier covering every input that affects the result.
    ///   - ttl: Maximum acceptable age in seconds.
    ///   - produce: Fetches a fresh value on a miss.
    public func cached<T: Codable>(
        _ key: String,
        ttl: TimeInterval,
        produce: () async throws -> T
    ) async throws -> T {
        if let data = data(for: key, ttl: ttl),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }

        let value = try await produce()

        if let encoded = try? JSONEncoder().encode(value) {
            store(encoded, for: key)
        }
        return value
    }

    // MARK: Maintenance

    /// Removes every entry for this tool.
    public func clear() throws {
        let directory = directoryURL
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// The number of entries and total bytes currently cached.
    public func usage() -> (entries: Int, bytes: Int) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return (0, 0) }

        let bytes = contents.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
        return (contents.count, bytes)
    }

    // MARK: Hashing

    /// FNV-1a, rendered as zero-padded hex.
    ///
    /// Hand-rolled rather than pulling in a crypto dependency: this names cache
    /// files, so collision resistance against an adversary is not the property
    /// being bought — only a stable, filesystem-safe spread over arbitrary
    /// request keys.
    static func digest(_ key: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016lx", hash)
    }
}
