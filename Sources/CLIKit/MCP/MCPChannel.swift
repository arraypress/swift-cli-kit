//
//  MCPChannel.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  `<tool> mcp --channel` — the same server, also pushing events into a
//  Claude Code session as they happen.
//
//  A channel is an MCP server that declares the `claude/channel` capability
//  and sends `notifications/claude/channel` unprompted; Claude Code delivers
//  each one to the model as a `<channel source="…">` block. Replies go out
//  through the tool's ordinary commands — nothing about the tools changes.
//
//  A channel that also declares `claude/channel/permission` is sent Claude
//  Code's tool-approval prompts, and may answer them for the person — the
//  relay that lets someone approve a command from their phone.
//
//  Claude Code only registers channels it is told to load (`--channels`, or
//  `--dangerously-load-development-channels` for one not on its allowlist),
//  so declaring the capability does nothing in any other client.
//

import Foundation

/// A tool whose `mcp` command can also run as a Claude Code channel.
public protocol MCPChannelProviding {

    /// The channel `mcp --channel` runs.
    ///
    /// - Throws: A ``CLIError`` when the channel cannot start — no permission,
    ///   nothing configured — which `mcp --channel` reports and exits on,
    ///   rather than serving tools that nobody will be told about.
    static func makeChannel() throws -> any MCPChannel
}

/// Something that pushes events into a Claude Code session.
public protocol MCPChannel: Sendable {

    /// Told to the model when the server connects: what the events are, and
    /// which tool answers them.
    var instructions: String { get }

    /// Channel capabilities beyond `claude/channel` itself — as
    /// `claude/channel/permission`, to be sent tool-approval prompts.
    var capabilities: [String] { get }

    /// Produces output until cancelled, handing each to `emit`.
    ///
    /// Started once the client has finished its handshake, never before — a
    /// notification ahead of the `initialize` reply is a protocol violation.
    func run(emit: @escaping @Sendable (MCPChannelOutput) -> Void) async throws

    /// Sees every tool call this server is about to run.
    ///
    /// For a channel whose own replies come back to it as events — a message
    /// sent to yourself arrives as one received — this is where it learns
    /// what it is sending, so it can recognise the echo. Before, not after:
    /// a command that confirms its own work can still be running when the
    /// echo arrives (measured: a send that checks delivery returned three
    /// seconds after its echo was written).
    func willRun(call arguments: [String])

    /// A notification from the client — for a permission channel,
    /// `notifications/claude/channel/permission_request`.
    ///
    /// Called on the thread reading stdin: anything slow belongs in a task
    /// of its own, or the server stops answering while it runs.
    func receive(notification method: String, params: [String: Any])
}

public extension MCPChannel {
    var capabilities: [String] { [] }
    func willRun(call arguments: [String]) {}
    func receive(notification method: String, params: [String: Any]) {}
}

/// What a channel sends the client.
public enum MCPChannelOutput: Sendable, Equatable {

    /// Something for the model to read.
    case event(MCPChannelEvent)

    /// The person's answer to a tool-approval prompt, by its request id.
    case permission(requestID: String, allow: Bool)
}

/// One event, as the model receives it.
public struct MCPChannelEvent: Sendable, Equatable {

    /// The body of the `<channel>` block.
    public let content: String

    /// Attributes on the `<channel>` block.
    ///
    /// Keys must be identifiers — letters, digits and underscores — or
    /// Claude Code drops them silently; ``sanitisedMeta`` enforces that.
    public let meta: [String: String]

    public init(content: String, meta: [String: String] = [:]) {
        self.content = content
        self.meta = meta
    }

    /// The attributes with every key made an identifier: anything else in it
    /// becomes `_`, so `image-path` arrives as `image_path` instead of not at
    /// all.
    var sanitisedMeta: [String: String] {
        var clean: [String: String] = [:]
        for (key, value) in meta {
            let name = String(key.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
            guard !name.isEmpty else { continue }
            clean[name] = value
        }
        return clean
    }
}
