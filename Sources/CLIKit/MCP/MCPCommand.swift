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

    @Flag(name: .long, help: "Also run as a Claude Code channel, pushing new events into the session (tools that have one).")
    var channel: Bool = false

    public func run() throws {
        // Both travel by environment: it reaches every per-call subprocess and
        // every in-process call alike, and a call's own arguments cannot undo
        // it — the schema offers neither flag.
        if readOnly { setenv(ReadOnlyMode.environmentKey, "1", 1) }
        if let wrapUntrusted { setenv(UntrustedPolicy.environmentKey, wrapUntrusted ? "1" : "0", 1) }

        // Made before serving, so a channel that cannot start says why and
        // exits, instead of a session that silently never hears anything.
        let events: (any MCPChannel)?
        if channel {
            guard let provider = Root.self as? MCPChannelProviding.Type else {
                throw CLIError.usage("\(Root.configuration.commandName ?? "this tool") has no channel")
            }
            events = try provider.makeChannel()
        } else {
            events = nil
        }

        let manifest = try Manifest.forTool(Root.self)
        let warm = (Root.self as? MCPKeepsWarm.Type)?.warmCommands ?? []
        let server = MCPServer(manifest: manifest, readOnly: ReadOnlyMode.isActive(),
                               channelInstructions: events?.instructions,
                               channelCapabilities: events?.capabilities ?? [],
                               localOnly: CommandEffects.localOnly(in: Root.self)) { arguments in
            // Awake for the call, never while idle on stdin waiting for the
            // next one: an assertion held for the server's lifetime would keep
            // a Mac up all night because an agent left its client open. A
            // subprocess call goes through CLIRunner, which holds its own.
            events?.willRun(call: arguments)
            if let first = arguments.first, warm.contains(first) {
                return KeepAwake.during(KeepAwake.reason(tool: manifest.tool, command: first)) {
                    InProcessInvocation.run(Root.self, arguments)
                }
            }
            return SelfInvocation.run(arguments)
        }

        server.serve(
            onReady: events.map { events in
                {
                    // Its own task, off the thread reading stdin. A channel
                    // that fails stops pushing; the tools keep answering.
                    Task.detached {
                        do {
                            try await events.run { server.emit($0) }
                        } catch {
                            Terminal.writeError("channel stopped: \(error)")
                        }
                    }
                }
            },
            onNotification: events.map { events in { events.receive(notification: $0, params: $1) } }
        )
    }
}
