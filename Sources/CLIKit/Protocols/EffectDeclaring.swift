//
//  EffectDeclaring.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A command saying whether it changes anything.
//

import Foundation

/// A command that declares its ``CommandEffect``.
///
/// Every ``CLICommand`` is one, with ``CommandEffect/undeclared`` as the
/// default and ``MutatingCommand`` defaulting to ``CommandEffect/acting(destructive:idempotent:)``.
/// A command that only reads must SAY so:
///
/// ```swift
/// struct ListCommand: CLICommand {
///     static let commandEffect = CommandEffect.readOnly
///     …
/// }
/// struct SendCommand: CLICommand {
///     static let commandEffect = CommandEffect.acting(destructive: false)
///     …
/// }
/// ```
///
/// The default is deliberately the unsafe-looking one. A forgotten
/// declaration on a command that sends would otherwise slip past
/// `--read-only`; as it is, a forgotten declaration on a command that only
/// reads gets it refused under `--read-only` — an annoyance that announces
/// itself — and ``CommandEffects/undeclared(in:)`` names it in a test.
public protocol EffectDeclaring {

    /// What running this command does to the world.
    static var commandEffect: CommandEffect { get }
}
