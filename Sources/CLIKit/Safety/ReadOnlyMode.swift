//
//  ReadOnlyMode.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  `--read-only` and `CLIKIT_READ_ONLY=1`: a backstop that lets a caller hand
//  an agent a tool and know it cannot send, write, move or delete anything.
//
//  THE GATE IS IN THE RUNNER, NOT IN THE COMMANDS. A check each command had
//  to remember to make would be missing from exactly the command that needed
//  it. ``CLICommand``'s `run()` and ``CLIRunner`` both ask before `execute()`
//  is reached, from each command's declared ``CommandEffect``, so a refused
//  command has opened nothing, resolved nothing and started nothing.
//

import ArgumentParser
import Foundation

/// Read-only mode: refuse every command that is not declared read-only.
public enum ReadOnlyMode {

    /// The environment variable that turns read-only mode on: `1`, `true` or
    /// `yes`. It reaches every tool in a process tree — `mcp`'s children
    /// included — which a flag cannot.
    public static let environmentKey = "CLIKIT_READ_ONLY"

    /// Whether read-only mode is on for this command.
    ///
    /// - Parameters:
    ///   - command: The parsed command, whose ``CommonOptions`` may carry
    ///     `--read-only`; `nil` consults only the environment.
    ///   - environment: The environment to read ``environmentKey`` from.
    public static func isActive(for command: Any? = nil,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment.flagIsSet(environmentKey) { return true }
        guard let command else { return false }
        return commonOptions(in: command)?.readOnly ?? false
    }

    /// Throws a usage error (exit 2, retry `not_started`) when read-only mode
    /// is on and `command` is not declared read-only.
    ///
    /// A ``MutatingCommand`` that is only planning — `--dry-run` — is let
    /// through: a plan changes nothing by that protocol's contract, and it is
    /// exactly what a cautious caller wants to see. So is a
    /// ``ConditionallyActing`` command whose arguments this time only read.
    public static func check(_ command: ParsableCommand,
                             environment: [String: String] = ProcessInfo.processInfo.environment) throws(CLIError) {
        let effect = CommandEffects.effect(of: type(of: command))
        guard !effect.isReadOnly, isActive(for: command, environment: environment) else { return }
        if let mutating = command as? any MutatingCommand, mutating.isPlanOnly { return }
        if let conditional = command as? any ConditionallyActing, !conditional.actsThisRun { return }
        throw refusal(name: type(of: command)._commandName, effect: effect, environment: environment)
    }

    /// The error a refused command leaves with.
    static func refusal(name: String, effect: CommandEffect, environment: [String: String]) -> CLIError {
        let source = environment.flagIsSet(environmentKey) ? "\(environmentKey) is set" : "--read-only was given"
        let what = effect.kind == .undeclared
            ? "`\(name)` has not declared that it only reads"
            : "`\(name)` changes things"
        return CLIError(
            code: .usage,
            message: "\(what), and read-only mode is on (\(source)); nothing was done",
            hint: "use a command that only reads, or run without --read-only and \(environmentKey)",
            retry: .notStarted
        )
    }

    /// The ``CommonOptions`` a parsed command carries, wherever it keeps them.
    ///
    /// Found by reflection so that no command has to hand them over: an
    /// `@OptionGroup var common: CommonOptions` directly, or one nested a few
    /// groups deep. Only ever called on a parsed command, so the group holds a
    /// value rather than its definition.
    static func commonOptions(in value: Any) -> CommonOptions? {
        search(value, depth: 0)
    }

    private static func search(_ value: Any, depth: Int) -> CommonOptions? {
        if let options = value as? CommonOptions { return options }
        if let group = value as? OptionGroup<CommonOptions> { return group.wrappedValue }
        guard depth < 6 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = search(child.value, depth: depth + 1) { return found }
        }
        return nil
    }
}
