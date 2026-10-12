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
public struct MCPCommand<Root: ParsableCommand & ServiceProviding>: ParsableCommand {

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

    public func run() throws {
        let manifest = try Manifest.forTool(Root.self)
        let warm = (Root.self as? MCPKeepsWarm.Type)?.warmCommands ?? []
        MCPServer(manifest: manifest) { arguments in
            if let first = arguments.first, warm.contains(first) {
                return InProcessInvocation.run(Root.self, arguments)
            }
            return SelfInvocation.run(arguments)
        }.serve()
    }
}
