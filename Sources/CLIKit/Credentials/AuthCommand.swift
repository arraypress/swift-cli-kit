//
//  AuthCommand.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The shared `auth` subcommand. Every service CLI gets login/status/logout by
//  declaring a ServiceSpec and adding one line to its subcommand list.
//

import ArgumentParser
import Foundation

// MARK: - Auth Command

/// `<tool> auth` — manage stored credentials.
///
/// Generic over the tool's ``ServiceProviding`` root so that all the prompts,
/// hints and storage keys derive from a single ``ServiceSpec``:
///
/// ```swift
/// CommandConfiguration(
///     commandName: "tmdb-meta",
///     subcommands: [Movie.self, Search.self, AuthCommand<TMDBMeta>.self]
/// )
/// ```
public struct AuthCommand<Provider: ServiceProviding>: ParsableCommand {

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "auth",
            abstract: "Manage stored \(Provider.service.displayName) credentials.",
            discussion: """
                Credentials resolve from the environment first, then from the \
                shared store. Environment variables always win, so CI and \
                one-off overrides never need to touch stored state.
                """,
            subcommands: [Login.self, Status.self, Logout.self],
            defaultSubcommand: Status.self
        )
    }

    public init() {}

    // MARK: Login

    /// `<tool> auth login` — prompt for and store secrets.
    public struct Login: ParsableCommand {

        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "login",
                abstract: "Store credentials for \(Provider.service.displayName)."
            )
        }

        public init() {}

        @Option(
            name: .long,
            help: "Which credential to set. Defaults to every one the service declares."
        )
        var key: String?

        @Flag(
            name: .long,
            help: "Read one secret from stdin instead of prompting. For scripts and CI."
        )
        var stdin: Bool = false

        public func run() throws {
            let service = Provider.service

            guard !service.isAnonymous else {
                Terminal.writeError("\(service.displayName) needs no credentials — nothing to store.")
                return
            }

            let store = FileCredentialStore()
            let targets: [CredentialSpec]

            if let key {
                guard let spec = service.credential(key) else {
                    let known = service.credentials.map(\.key).joined(separator: ", ")
                    throw ValidationError("Unknown credential '\(key)'. Known keys: \(known).")
                }
                targets = [spec]
            } else {
                targets = service.credentials
            }

            if stdin && targets.count > 1 {
                throw ValidationError(
                    "--stdin sets a single credential; pass --key to say which one."
                )
            }

            if let signupURL = service.signupURL, !stdin {
                Terminal.writeError("Get credentials at: \(signupURL)\n")
            }

            var stored = 0
            for spec in targets {
                let optionalNote = spec.isRequired ? "" : " (optional, press return to skip)"
                let secret: String?

                if stdin {
                    secret = SecurePrompt.readPipedSecret()
                } else {
                    secret = SecurePrompt.readSecret(
                        "\(service.displayName) \(spec.label)\(optionalNote): "
                    )
                }

                guard let secret, !secret.isEmpty else {
                    if spec.isRequired && !stdin {
                        Terminal.writeError("  skipped \(spec.label)")
                    }
                    continue
                }

                try store.write(service: service.id, key: spec.key, value: secret)
                stored += 1
                Terminal.writeError("  saved \(spec.label) (\(CredentialResolver.mask(secret)))")
            }

            guard stored > 0 else {
                throw CLIError.usage(
                    "No credentials were stored",
                    hint: "run: \(service.toolName) auth login"
                )
            }

            Terminal.writeError("\nStored in \(store.locationDescription) (mode 600).")
        }
    }

    // MARK: Status

    /// `<tool> auth status` — report what is configured and from where.
    ///
    /// Exits `3` when a required credential is missing, so a caller can probe
    /// readiness without parsing the output.
    public struct Status: ParsableCommand {

        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "status",
                abstract: "Show which credentials are configured, and their source.",
                discussion: "Exits 3 if a required credential is missing."
            )
        }

        public init() {}

        @Flag(name: .long, help: "Force JSON output (the default when piped).")
        var json: Bool = false

        public func run() throws {
            let service = Provider.service
            let store = FileCredentialStore()
            let resolver = CredentialResolver(service: service, store: store)

            let report = AuthStatusReport(
                service: service.id,
                displayName: service.displayName,
                anonymous: service.isAnonymous,
                storeLocation: store.locationDescription,
                credentials: try resolver.statuses()
            )

            let format: OutputFormat = json ? .json : OutputFormat.resolve(explicit: nil)
            try Emitter(format: format).emit(report)

            if !report.ready {
                throw ExitCode(CLIExitCode.authRequired.rawValue)
            }
        }
    }

    // MARK: Logout

    /// `<tool> auth logout` — remove stored secrets.
    public struct Logout: ParsableCommand {

        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "logout",
                abstract: "Remove stored \(Provider.service.displayName) credentials."
            )
        }

        public init() {}

        @Option(name: .long, help: "Remove a single credential rather than all of them.")
        var key: String?

        public func run() throws {
            let service = Provider.service
            let store = FileCredentialStore()

            if let key {
                guard service.credential(key) != nil else {
                    let known = service.credentials.map(\.key).joined(separator: ", ")
                    throw ValidationError("Unknown credential '\(key)'. Known keys: \(known).")
                }
                try store.delete(service: service.id, key: key)
                Terminal.writeError("Removed \(service.displayName) \(key).")
            } else {
                try store.deleteAll(service: service.id)
                Terminal.writeError("Removed all stored \(service.displayName) credentials.")
            }

            // Environment variables outlive the store, and a user who thinks
            // they have logged out while a shell export still supplies the key
            // is owed the correction.
            let environment = ProcessInfo.processInfo.environment
            let stillSet = service.credentials
                .flatMap(\.envNames)
                .filter { environment[$0]?.isEmpty == false }

            if !stillSet.isEmpty {
                Terminal.writeError(
                    "note: still set in your environment: \(stillSet.joined(separator: ", "))"
                )
            }
        }
    }
}

// MARK: - Status Report

/// The payload `auth status` emits.
///
/// Encode-only: ``ready`` is derived, so there is no round trip to preserve and
/// nothing reads this back.
public struct AuthStatusReport: Encodable, TextRenderable, Sendable {

    /// The service identifier, e.g. `"tmdb"`.
    public let service: String

    /// The display name, e.g. `"TMDB"`.
    public let displayName: String

    /// Whether the service needs no credentials at all.
    public let anonymous: Bool

    /// Where stored secrets live on disk.
    public let storeLocation: String

    /// One entry per declared credential.
    public let credentials: [CredentialStatus]

    /// Whether every required credential resolved.
    public var ready: Bool {
        credentials.allSatisfy { !$0.isRequired || $0.source != .missing }
    }

    private enum CodingKeys: String, CodingKey {
        case service, displayName, anonymous, storeLocation, credentials, ready
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(service, forKey: .service)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(anonymous, forKey: .anonymous)
        try container.encode(storeLocation, forKey: .storeLocation)
        try container.encode(credentials, forKey: .credentials)
        // Computed, but callers want it in the JSON — it is the single field an
        // agent actually branches on.
        try container.encode(ready, forKey: .ready)
    }

    public func renderText() -> String {
        if anonymous {
            return "\(displayName) needs no credentials."
        }

        var lines = ["\(displayName) credentials:"]
        for credential in credentials {
            let mark: String
            switch credential.source {
            case .environment: mark = "✓"
            case .store: mark = "✓"
            case .missing: mark = credential.isRequired ? "✗" : "-"
            }

            let origin: String
            switch credential.source {
            case .environment: origin = "from $\(credential.envName ?? "env")"
            case .store: origin = "from store"
            case .missing: origin = credential.isRequired ? "missing" : "not set (optional)"
            }

            let preview = credential.preview.map { " \($0)" } ?? ""
            lines.append("  \(mark) \(credential.label)\(preview) — \(origin)")
        }
        lines.append("")
        lines.append("Store: \(storeLocation)")
        return lines.joined(separator: "\n")
    }
}
