//
//  CredentialResolver.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Resolves a secret from the environment or the store, in that order, and
//  produces a self-repairing error when it finds neither.
//

import Foundation

// MARK: - Credential Status

/// Where a credential's value came from. Reported by `auth status`.
public struct CredentialStatus: Sendable, Codable, Equatable {

    /// The origin of a resolved value.
    public enum Source: String, Sendable, Codable {
        case environment
        case store
        case missing
    }

    /// The credential key, e.g. `"api_key"`.
    public let key: String

    /// The human label, e.g. `"API key"`.
    public let label: String

    /// Whether the service is unusable without it.
    public let isRequired: Bool

    /// Where the value was found.
    public let source: Source

    /// The environment variable that supplied it, when ``source`` is
    /// ``Source/environment``.
    public let envName: String?

    /// A masked preview of the value, e.g. `"••••a1b2"`. Never the real secret.
    public let preview: String?
}

// MARK: - Credential Resolver

/// Resolves a service's secrets.
///
/// Precedence is environment first, then the store. Environment wins so that a
/// one-off override, a CI secret, or a container variable never requires
/// touching persistent state — and so that the value the underlying library
/// would read through its own `Configuration.default` is the value the CLI uses.
public struct CredentialResolver: Sendable {

    /// The service being resolved for.
    public let service: ServiceSpec

    /// Where persistent secrets live.
    public let store: CredentialStore

    public init(service: ServiceSpec, store: CredentialStore = FileCredentialStore()) {
        self.service = service
        self.store = store
    }

    // MARK: Resolution

    /// Resolves a credential, returning `nil` when it is absent everywhere.
    ///
    /// - Parameter key: The credential key declared in the ``ServiceSpec``.
    public func resolve(_ key: String) throws -> String? {
        guard let spec = service.credential(key) else { return nil }
        if let (value, _) = environmentValue(for: spec) { return value }
        return try store.read(service: service.id, key: key)
    }

    /// Resolves a credential or throws a ``CLIError`` that says how to supply it.
    ///
    /// The thrown error carries a `hint` naming this tool's own login command,
    /// which is what lets an automated caller fix the problem instead of
    /// escalating it.
    ///
    /// - Parameter key: The credential key declared in the ``ServiceSpec``.
    public func require(_ key: String) throws -> String {
        if let value = try resolve(key), !value.isEmpty { return value }

        let spec = service.credential(key)
        let label = spec?.label ?? key
        var hint = "run: \(service.toolName) auth login"
        if let envName = spec?.envNames.first {
            hint += "  (or export \(envName))"
        }
        if let signupURL = service.signupURL {
            hint += "\n  get one at: \(signupURL)"
        }

        throw CLIError.authRequired(
            "\(service.displayName) \(label) not found",
            service: service.id,
            hint: hint
        )
    }

    // MARK: Status

    /// Reports the state of every declared credential, for `auth status`.
    public func statuses() throws -> [CredentialStatus] {
        try service.credentials.map { spec in
            if let (value, envName) = environmentValue(for: spec) {
                return CredentialStatus(
                    key: spec.key,
                    label: spec.label,
                    isRequired: spec.isRequired,
                    source: .environment,
                    envName: envName,
                    preview: Self.mask(value)
                )
            }
            if let value = try store.read(service: service.id, key: spec.key), !value.isEmpty {
                return CredentialStatus(
                    key: spec.key,
                    label: spec.label,
                    isRequired: spec.isRequired,
                    source: .store,
                    envName: nil,
                    preview: Self.mask(value)
                )
            }
            return CredentialStatus(
                key: spec.key,
                label: spec.label,
                isRequired: spec.isRequired,
                source: .missing,
                envName: nil,
                preview: nil
            )
        }
    }

    // MARK: Helpers

    /// The first non-empty environment variable matching the spec.
    private func environmentValue(for spec: CredentialSpec) -> (value: String, name: String)? {
        let environment = ProcessInfo.processInfo.environment
        for name in spec.envNames {
            if let value = environment[name], !value.isEmpty {
                return (value, name)
            }
        }
        return nil
    }

    /// Masks a secret down to a recognisable but useless preview.
    ///
    /// Short values are fully hidden — revealing the last four characters of an
    /// eight-character secret gives away half of it.
    static func mask(_ value: String) -> String {
        guard value.count >= 12 else { return String(repeating: "•", count: 8) }
        return String(repeating: "•", count: 4) + value.suffix(4)
    }
}
