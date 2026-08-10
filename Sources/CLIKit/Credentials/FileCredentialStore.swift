//
//  FileCredentialStore.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The default backend: one 0600 JSON file, shared by every tool in the family.
//

import Foundation

/// Stores credentials in a mode-`0600` JSON file under the user's config
/// directory.
///
/// One file serves every tool in the family, namespaced by service:
///
/// ```json
/// {
///   "version": 1,
///   "credentials": {
///     "tmdb":    { "api_key": "…" },
///     "discogs": { "token": "…" }
///   }
/// }
/// ```
///
/// A shared file is what makes many small binaries workable — `tmdb-meta auth
/// login` and `discogs-meta auth login` write to the same place, and any tool
/// can report on the others in `auth status`.
public struct FileCredentialStore: CredentialStore {

    // MARK: Properties

    /// The directory namespace, e.g. `"arraypress"`.
    public let namespace: String

    /// Whether to warn on stderr when the file's permissions are too open.
    public let warnsOnLoosePermissions: Bool

    // MARK: Initialisation

    /// - Parameters:
    ///   - namespace: The config subdirectory name. Shared across the family.
    ///   - warnsOnLoosePermissions: Emit a stderr warning if the file is group-
    ///     or world-readable. Defaults to true.
    public init(namespace: String = "arraypress", warnsOnLoosePermissions: Bool = true) {
        self.namespace = namespace
        self.warnsOnLoosePermissions = warnsOnLoosePermissions
    }

    // MARK: Locations

    /// The config directory, honouring `XDG_CONFIG_HOME`.
    private var directoryURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent(namespace, isDirectory: true)
    }

    /// The credentials file itself.
    public var fileURL: URL {
        directoryURL.appendingPathComponent("credentials.json", isDirectory: false)
    }

    public var locationDescription: String {
        fileURL.path
    }

    // MARK: CredentialStore

    public func read(service: String, key: String) throws -> String? {
        try load().credentials[service]?[key]
    }

    public func write(service: String, key: String, value: String) throws {
        var store = try load()
        var forService = store.credentials[service] ?? [:]
        forService[key] = value
        store.credentials[service] = forService
        try save(store)
    }

    public func delete(service: String, key: String) throws {
        var store = try load()
        guard var forService = store.credentials[service] else { return }
        forService.removeValue(forKey: key)
        if forService.isEmpty {
            store.credentials.removeValue(forKey: service)
        } else {
            store.credentials[service] = forService
        }
        try save(store)
    }

    public func deleteAll(service: String) throws {
        var store = try load()
        guard store.credentials.removeValue(forKey: service) != nil else { return }
        try save(store)
    }

    public func storedServices() throws -> [String] {
        try load().credentials.keys.sorted()
    }

    // MARK: Persistence

    private struct Contents: Codable {
        var version: Int
        var credentials: [String: [String: String]]

        static let empty = Contents(version: 1, credentials: [:])
    }

    private func load() throws -> Contents {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }

        checkPermissions(of: url)

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CLIError(
                code: .upstream,
                message: "Could not read credentials at \(url.path): \(error.localizedDescription)"
            )
        }

        guard !data.isEmpty else { return .empty }

        do {
            return try JSONDecoder().decode(Contents.self, from: data)
        } catch {
            // Refuse rather than silently starting fresh — overwriting a
            // malformed credentials file would destroy secrets the user may not
            // have recorded anywhere else.
            throw CLIError(
                code: .usage,
                message: "Credentials file at \(url.path) is malformed",
                hint: "inspect or remove it, then run auth login again"
            )
        }
    }

    private func save(_ contents: Contents) throws {
        let directory = directoryURL
        let manager = FileManager.default

        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(contents)

        // Create the replacement with restrictive permissions from the start,
        // then move it into place. Writing the real file directly would leave a
        // window in which secrets sat on disk at the default mode.
        let temporaryURL = directory.appendingPathComponent(
            ".credentials.\(UUID().uuidString).tmp",
            isDirectory: false
        )

        guard manager.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CLIError(code: .upstream, message: "Could not write to \(directory.path)")
        }

        let destination = fileURL
        do {
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporaryURL)
                // replaceItemAt can carry over the original's attributes.
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            } else {
                try manager.moveItem(at: temporaryURL, to: destination)
            }
        } catch {
            try? manager.removeItem(at: temporaryURL)
            throw CLIError(
                code: .upstream,
                message: "Could not save credentials: \(error.localizedDescription)"
            )
        }
    }

    // MARK: Permissions

    /// Warns when the credentials file is readable beyond its owner.
    ///
    /// Warns rather than refuses. `ssh` hard-fails here, but a metadata lookup
    /// is not a login: breaking someone's pipeline over a mode bit costs more
    /// than it protects, and the message still tells them how to fix it.
    private func checkPermissions(of url: URL) {
        guard warnsOnLoosePermissions else { return }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber else { return }

        let mode = permissions.uint16Value
        guard mode & 0o077 != 0 else { return }

        Terminal.writeError(
            "warning: \(url.path) is readable by other users (mode \(String(mode, radix: 8)))\n"
            + "  hint: chmod 600 \(url.path)"
        )
    }
}
