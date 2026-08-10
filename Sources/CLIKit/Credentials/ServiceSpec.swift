//
//  ServiceSpec.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  How a tool declares the credentials it needs. Everything the shared auth
//  command knows about a service comes from one of these.
//

import Foundation

// MARK: - Credential Spec

/// A single secret a service requires.
public struct CredentialSpec: Sendable {

    /// The key this secret is stored under, e.g. `"api_key"`. snake_case.
    public let key: String

    /// A human label used in prompts, e.g. `"API key"`.
    public let label: String

    /// Environment variables checked before the store, in order.
    ///
    /// These deliberately match the names the underlying library already reads
    /// in its own `Configuration.default`, so a user who has exported
    /// `TMDB_API_KEY` for library use gets the CLI working for free.
    public let envNames: [String]

    /// Whether the service is unusable without this secret.
    ///
    /// Optional credentials are real: an unauthenticated GitHub request works
    /// fine, it just gets a much lower rate limit.
    public let isRequired: Bool

    public init(key: String, label: String, envNames: [String], isRequired: Bool = true) {
        self.key = key
        self.label = label
        self.envNames = envNames
        self.isRequired = isRequired
    }
}

// MARK: - Service Spec

/// Everything the shared auth machinery needs to know about one service.
public struct ServiceSpec: Sendable {

    /// The stable identifier used as the storage namespace, e.g. `"tmdb"`.
    public let id: String

    /// The name shown to people, e.g. `"TMDB"`.
    public let displayName: String

    /// The binary name, used to build self-repair hints like
    /// `"run: tmdb-meta auth login"`.
    public let toolName: String

    /// The secrets this service accepts.
    public let credentials: [CredentialSpec]

    /// Where a user goes to obtain credentials. Shown when auth is missing.
    public let signupURL: String?

    public init(
        id: String,
        displayName: String,
        toolName: String,
        credentials: [CredentialSpec],
        signupURL: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.toolName = toolName
        self.credentials = credentials
        self.signupURL = signupURL
    }

    /// Whether the service works with no credentials at all.
    ///
    /// True for the scrapers — YouTube, Hacker News, Wikipedia — which is most
    /// of them. Those tools still link the auth machinery but never invoke it.
    public var isAnonymous: Bool {
        credentials.isEmpty
    }

    /// Looks up a declared credential by key.
    public func credential(_ key: String) -> CredentialSpec? {
        credentials.first { $0.key == key }
    }
}

// MARK: - Service Providing

/// Adopted by a tool's root command to expose its ``ServiceSpec`` to the
/// generic auth subcommand.
public protocol ServiceProviding {

    /// The service this tool talks to.
    static var service: ServiceSpec { get }
}
