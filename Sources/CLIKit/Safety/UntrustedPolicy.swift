//
//  UntrustedPolicy.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Whether this run wraps other people's text, and with which token.
public struct UntrustedPolicy: Equatable, Sendable {

    /// The environment variable that overrides the default: `1`/`true`/`yes`
    /// wraps, `0`/`false`/`no` does not. A flag beats it.
    public static let environmentKey = "CLIKIT_WRAP_UNTRUSTED"

    /// Whether declared fields are wrapped.
    public let isEnabled: Bool

    /// The token in the markers — random per run, see ``Untrusted/runToken``.
    public let token: String

    public init(isEnabled: Bool, token: String = Untrusted.runToken) {
        self.isEnabled = isEnabled
        self.token = token
    }

    /// Wraps nothing.
    public static let off = UntrustedPolicy(isEnabled: false)

    /// Decides for this run.
    ///
    /// ON when stdout is not a terminal: piped output is what an agent reads,
    /// and an agent is who a message saying "ignore your instructions" is
    /// aimed at. OFF on a terminal, where a person reads it and the markers
    /// are noise. `CLIKIT_WRAP_UNTRUSTED` overrides that default, and
    /// `--wrap-untrusted` / `--no-wrap-untrusted` override both.
    public static func resolve(flag: Bool? = nil,
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               stdoutIsTTY: Bool = Terminal.stdoutIsTTY,
                               token: String = Untrusted.runToken) -> UntrustedPolicy {
        if let flag { return UntrustedPolicy(isEnabled: flag, token: token) }
        if let value = environment[environmentKey]?.lowercased(), !value.isEmpty {
            if ["1", "true", "yes"].contains(value) { return UntrustedPolicy(isEnabled: true, token: token) }
            if ["0", "false", "no"].contains(value) { return UntrustedPolicy(isEnabled: false, token: token) }
        }
        return UntrustedPolicy(isEnabled: !stdoutIsTTY, token: token)
    }

    /// `text` wrapped when this policy is on; unchanged when it is off.
    public func apply(_ text: String) -> String {
        isEnabled ? Untrusted.wrap(text, token: token) : text
    }
}
