//
//  CommandEffect.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  What running a command does to the world: nothing, or something.
//

import Foundation

/// Whether a command only reads, or acts — and if it acts, how.
///
/// Every command declares one through ``EffectDeclaring/commandEffect``. It
/// drives three things: `--read-only` refuses anything that is not
/// ``readOnly``; `describe` lists it per command; and `mcp` turns it into the
/// tool annotations MCP clients use to decide what needs a person's OK
/// (`readOnlyHint`, `destructiveHint`, `idempotentHint`).
public struct CommandEffect: Codable, Equatable, Hashable, Sendable {

    /// The three answers a command can give.
    public enum Kind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        /// Reads only. Changes nothing outside this process except caches.
        case readOnly = "read_only"
        /// Changes something: sends, writes, moves, deletes, opens a draft.
        case acting
        /// Never said. Treated as acting — refused under `--read-only`, and no
        /// read-only hint over MCP — so forgetting fails closed.
        case undeclared
    }

    /// Which of the three.
    public let kind: Kind

    /// Whether it may delete or overwrite (MCP's `destructiveHint`) rather
    /// than only add. Meaningless for a read.
    public let destructive: Bool

    /// Whether running it twice with the same arguments does no more than
    /// running it once (MCP's `idempotentHint`). Meaningless for a read.
    public let idempotent: Bool

    public init(kind: Kind, destructive: Bool, idempotent: Bool) {
        self.kind = kind
        self.destructive = destructive
        self.idempotent = idempotent
    }

    /// Reads only: list, read, search, show, describe.
    public static let readOnly = CommandEffect(kind: .readOnly, destructive: false, idempotent: true)

    /// Changes something.
    ///
    /// - Parameters:
    ///   - destructive: Whether it may delete or overwrite. `true` is MCP's own
    ///     default, and the right one when unsure. A send or a create that only
    ///     ADDS is `false` — irreversible is not the same as destructive.
    ///   - idempotent: Whether repeating it changes nothing more — setting a
    ///     flag is; sending a message is not.
    public static func acting(destructive: Bool = true, idempotent: Bool = false) -> CommandEffect {
        CommandEffect(kind: .acting, destructive: destructive, idempotent: idempotent)
    }

    /// No declaration. Handled as the most cautious kind of acting command.
    public static let undeclared = CommandEffect(kind: .undeclared, destructive: true, idempotent: false)

    /// Whether this command only reads.
    public var isReadOnly: Bool { kind == .readOnly }
}
