//
//  CredentialStore.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The storage abstraction. A protocol rather than a concrete type so the
//  backend can change without touching any of the service CLIs.
//

import Foundation

/// Persistent storage for service credentials.
///
/// The shipped implementation is ``FileCredentialStore``, which writes a
/// `0600` JSON file — the same approach `gh`, `aws`, `docker` and `npm` take.
///
/// ## Why not the Keychain
///
/// Keychain ACLs are bound to code signature. A Swift binary built by SwiftPM or
/// installed from a Homebrew bottle is ad-hoc signed, so its code identity
/// changes on every rebuild and every version bump; a keychain item written by
/// one build prompts when read by the next. That breaks worse under this
/// project's shape specifically, where many separate binaries share one store:
/// `tmdb-meta` writing an item that `discogs-meta` must read is a cross-identity
/// access, and therefore a GUI prompt.
///
/// The decisive problem is headless use. An agent invoking these tools from a
/// background process, over SSH, or in CI meets either a locked keychain
/// (`errSecInteractionNotAllowed`) or a dialog that hangs the call — worse than
/// a clean failure.
///
/// The security gap is also narrower than it appears: the login keychain is
/// unlocked for the whole session, so both it and a `0600` file are readable by
/// any process running as the user. Keychain's real edge is encryption at rest
/// against offline disk access, which FileVault already covers.
///
/// A keychain backend remains a reasonable opt-in for someone who signs their
/// binaries with a stable Developer ID. Conform a new type here and no service
/// CLI needs to change.
public protocol CredentialStore: Sendable {

    /// Reads a stored secret, or `nil` if absent.
    func read(service: String, key: String) throws -> String?

    /// Writes a secret, replacing any existing value.
    func write(service: String, key: String, value: String) throws

    /// Removes a single secret. Absent keys are not an error.
    func delete(service: String, key: String) throws

    /// Removes every secret for a service. Absent services are not an error.
    func deleteAll(service: String) throws

    /// The services that currently have at least one stored secret.
    func storedServices() throws -> [String]

    /// A human-readable description of where secrets live, for `auth status`.
    var locationDescription: String { get }
}
