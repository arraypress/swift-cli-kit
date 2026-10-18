//
//  MCPCommand.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  `<tool> mcp` — serve this tool's commands over stdio.
//

import ArgumentParser
import Foundation

/// `<tool> mcp` — serve this tool's commands over the Model Context Protocol.
public struct MCPCommand<Root: ParsableCommand & ServiceProviding>: ParsableCommand, HoldsOwnPowerAssertion, EffectDeclaring {

    /// Serving changes nothing; each call is judged by its own command.
    public static var commandEffect: CommandEffect { .readOnly }

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "mcp",
            abstract: "Serve this tool's commands over MCP on stdio.",
            discussion: """
                Speaks newline-delimited JSON-RPC on stdin/stdout, exposing one \
                MCP tool per command. Register it with an MCP client:

                  { "mcpServers": { "<name>": { "command": "<tool>", "args": ["mcp"] } } }

                Credentials are resolved by this process, so the client never \
                holds them.
                """
        )
    }

    public init() {}

    @Flag(name: .long, help: "Offer only commands that read, and refuse the rest — also CLIKIT_READ_ONLY=1.")
    var readOnly: Bool = false

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Mark other people's text as <<untrusted:…>> in every result (default: on).")
    var wrapUntrusted: Bool?

    public func run() throws {
        // Both travel by environment: it reaches every per-call subprocess and
        // every in-process call alike, and a call's own arguments cannot undo
        // it — the schema offers neither flag.
        if readOnly { setenv(ReadOnlyMode.environmentKey, "1", 1) }
        if let wrapUntrusted { setenv(UntrustedPolicy.environmentKey, wrapUntrusted ? "1" : "0", 1) }

        let manifest = try Manifest.forTool(Root.self)
        let warm = (Root.self as? MCPKeepsWarm.Type)?.warmCommands ?? []
        MCPServer(manifest: manifest, readOnly: ReadOnlyMode.isActive()) { arguments in
            // Awake for the call, never while idle on stdin waiting for the
            // next one: an assertion held for the server's lifetime would keep
            // a Mac up all night because an agent left its client open. A
            // subprocess call goes through CLIRunner, which holds its own.
            if let first = arguments.first, warm.contains(first) {
                return KeepAwake.during(KeepAwake.reason(tool: manifest.tool, command: first)) {
                    InProcessInvocation.run(Root.self, arguments)
                }
            }
            return SelfInvocation.run(arguments)
        }.serve()
    }
}
