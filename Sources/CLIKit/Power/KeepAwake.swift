//
//  KeepAwake.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Keeps the Mac out of idle sleep while a command is working.
//
//  Measured, not imagined: on a Mac whose system sleep is set to one minute,
//  a model-training job started in the background ran its first ~20 steps at
//  5 s each and then crawled at 60–80 s a step "at 99% GPU". It was neither
//  heat nor a second GPU user — the machine had gone to sleep, and the work
//  only advanced in the short DarkWake windows the system grants. A person
//  at the keyboard never sees it; an agent driving a tool from a background
//  shell sees nothing else.
//
//  So ``CLIRunner`` holds an assertion for exactly the length of every
//  command — the same `PreventUserIdleSystemSleep` that `caffeinate -i`
//  takes — and `mcp` holds one per tool call, never while idle on stdin.
//  `NO_KEEP_AWAKE=1` turns it off.
//

import Foundation

/// Holds the Mac out of idle sleep for the length of some work.
///
/// ```swift
/// let pages = try await KeepAwake.during("ocr: reading") { try await read(folder) }
/// ```
public enum KeepAwake {

    /// The environment variable that turns keep-awake off.
    public static let disableKey = "NO_KEEP_AWAKE"

    /// Whether commands may keep the Mac awake in this environment.
    public static func isAllowed(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !environment.flagIsSet(disableKey)
    }

    /// Takes an assertion named `reason` — it is what `pmset -g assertions`
    /// shows, so name the tool: `"imagine make: working"`.
    ///
    /// - Returns: The token to release, or `nil` when keep-awake is off or the
    ///   system refused (which is never worth failing a command over).
    public static func hold(_ reason: String) -> KeepAwakeToken? {
        hold(reason, environment: ProcessInfo.processInfo.environment, assertions: SystemPowerAssertions())
    }

    /// Runs `body` with the Mac held awake.
    public static func during<T, E: Error>(
        _ reason: String,
        _ body: () async throws(E) -> T
    ) async throws(E) -> T {
        let token = hold(reason)
        defer { token?.release() }
        return try await body()
    }

    /// Runs synchronous `body` with the Mac held awake.
    public static func during<T, E: Error>(
        _ reason: String,
        _ body: () throws(E) -> T
    ) throws(E) -> T {
        let token = hold(reason)
        defer { token?.release() }
        return try body()
    }

    /// The assertion name for a command: `"imagine make: working"`, or just
    /// `"imagine: working"` when the command is the tool itself.
    static func reason(tool: String, command: String?) -> String {
        guard let command, !command.isEmpty, command != tool else { return "\(tool): working" }
        return "\(tool) \(command): working"
    }

    /// The seam the tests use.
    static func hold(
        _ reason: String,
        environment: [String: String],
        assertions: any PowerAssertions
    ) -> KeepAwakeToken? {
        guard isAllowed(environment: environment), let id = assertions.create(name: reason) else { return nil }
        return KeepAwakeToken(id: id, assertions: assertions)
    }
}

/// A command that manages its own keep-awake, so ``CLIRunner`` does not hold
/// one around it — `mcp`, which idles on stdin between calls and holds one per
/// call instead.
protocol HoldsOwnPowerAssertion {}
