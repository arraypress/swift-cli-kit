//
//  LocalOnlyCommand.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A command only the person at the terminal may run.
//

import ArgumentParser

/// A command never offered over MCP.
///
/// For commands whose authority belongs to the person at the keyboard, not
/// to an agent: who may message a channel, which keys a tool trusts. Offered
/// as a tool, such a command is one well-worded message away from an agent
/// granting a stranger access because the stranger asked — exactly what a
/// prompt injection asks for. It stays in `--help` and `describe`; `mcp`
/// leaves it out of `tools/list` and refuses it in `tools/call`.
///
/// On a group, it covers every subcommand beneath it.
public protocol LocalOnlyCommand {}

public extension CommandEffects {

    /// The paths of every invocable command `mcp` must not offer: those
    /// declared ``LocalOnlyCommand``, and everything under a group that is.
    static func localOnly<Root: ParsableCommand>(in root: Root.Type) -> Set<[String]> {
        var found: Set<[String]> = []
        func walk(_ node: ParsableCommand.Type, path: [String], inherited: Bool) {
            let local = inherited || node is LocalOnlyCommand.Type
            let configuration = node.configuration
            let children = configuration.subcommands
            if children.isEmpty || configuration.defaultSubcommand != nil, local {
                found.insert(path)
            }
            for child in children {
                walk(child, path: path + [child._commandName], inherited: local)
            }
        }
        walk(root, path: [], inherited: false)
        return found
    }
}
