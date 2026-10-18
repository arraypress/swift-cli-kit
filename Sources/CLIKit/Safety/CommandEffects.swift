//
//  CommandEffects.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Every command's declared effect, read off the command tree itself.
//

import ArgumentParser
import Foundation

/// Reads each command's ``CommandEffect`` off a tool's command tree.
public enum CommandEffects {

    /// The effect a command type declares, or ``CommandEffect/undeclared``.
    public static func effect(of type: Any.Type) -> CommandEffect {
        (type as? EffectDeclaring.Type)?.commandEffect ?? .undeclared
    }

    /// Every invocable command under `root`, keyed by its subcommand path —
    /// the same path ``Manifest/Command/path`` carries.
    public static func table<Root: ParsableCommand>(for root: Root.Type) -> [[String]: CommandEffect] {
        var table: [[String]: CommandEffect] = [:]
        for (path, type) in invocable(root) { table[path] = effect(of: type) }
        return table
    }

    /// The invocations of every command that never declared its effect —
    /// `["notes list", "notes move"]`. A tool's tests assert this is empty:
    ///
    /// ```swift
    /// XCTAssertEqual(CommandEffects.undeclared(in: Notes.self), [])
    /// ```
    public static func undeclared<Root: ParsableCommand>(in root: Root.Type) -> [String] {
        invocable(root)
            .filter { effect(of: $0.type).kind == .undeclared }
            .map { ([root._commandName] + $0.path).joined(separator: " ") }
            .sorted()
    }

    /// The invocations of every command declared as acting (or undeclared,
    /// which is handled as acting) — what `--read-only` refuses.
    public static func refusedUnderReadOnly<Root: ParsableCommand>(in root: Root.Type) -> [String] {
        invocable(root)
            .filter { !effect(of: $0.type).isReadOnly }
            .map { ([root._commandName] + $0.path).joined(separator: " ") }
            .sorted()
    }

    /// Every command that can be run, with its path and the type that runs it.
    ///
    /// The rule `describe` uses: a leaf runs; a group runs only through its
    /// default subcommand, and then carries that subcommand's effect.
    static func invocable<Root: ParsableCommand>(_ root: Root.Type) -> [(path: [String], type: ParsableCommand.Type)] {
        var found: [(path: [String], type: ParsableCommand.Type)] = []

        func walk(_ node: ParsableCommand.Type, path: [String]) {
            let configuration = node.configuration
            let children = configuration.subcommands
            if children.isEmpty {
                found.append((path, node))
            } else if let fallback = configuration.defaultSubcommand {
                found.append((path, fallback))
            }
            for child in children { walk(child, path: path + [child._commandName]) }
        }

        walk(root, path: [])
        return found
    }
}
