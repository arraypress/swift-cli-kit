//
//  ToolIndex.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Many tools' manifests merged into one document.
//

import Foundation

/// Every tool in the family, described in a single file.
///
/// Built by collecting each tool's `describe --json` output, so a directory
/// rendered from this is generated rather than curated — publishing a tool
/// updates the listing, and nothing is maintained twice.
///
/// It is also what an agent should fetch instead of discovering binaries one at
/// a time: one request, every command, every argument, every exit code.
public struct ToolIndex: Codable, Sendable {

    // MARK: Entry

    /// One tool's place in the index.
    public struct Entry: Codable, Sendable {

        public let tool: String
        public let version: String
        public let service: String

        /// Whether the tool is unusable without a credential.
        ///
        /// Distinct from "has a credential": Discogs takes an optional token and
        /// is perfectly usable without one, so it appears here as `false`.
        public let requiresAuth: Bool

        /// The tool's own one-line abstract, taken from its root command.
        public let summary: String?

        /// How many invocable commands it exposes.
        public let commandCount: Int

        public let formats: [String]
        public let commands: [Manifest.Command]
    }

    // MARK: Properties

    /// When the index was built, ISO-8601.
    ///
    /// Supplied by the caller rather than read from the clock, so a build that
    /// changes nothing produces a byte-identical file and does not churn the
    /// repository on every CI run.
    public let generated: String?

    public let toolCount: Int

    /// Total invocable commands across every tool.
    public let commandCount: Int

    public let tools: [Entry]

    // MARK: Building

    /// Merges manifests into one index.
    ///
    /// - Parameters:
    ///   - manifests: One per tool, in any order.
    ///   - generated: A timestamp to stamp, or `nil` to omit it.
    public static func build(from manifests: [Manifest], generated: Date? = nil) -> ToolIndex {
        // One entry per tool name, first occurrence winning. The same binary
        // reachable two ways — a name and a path, or two PATH entries — must
        // not count twice; deduplicating *before* the sort keeps the winner
        // deterministic, because `sorted` makes no promise about the order of
        // equal names.
        var seen = Set<String>()
        let unique = manifests.filter { seen.insert($0.tool).inserted }

        // Sorted by name so the output is stable across runs regardless of the
        // order tools were discovered in — otherwise every rebuild is a diff.
        let entries = unique
            .sorted { $0.tool.localizedCaseInsensitiveCompare($1.tool) == .orderedAscending }
            .map { manifest in
                Entry(
                    tool: manifest.tool,
                    version: manifest.version,
                    service: manifest.service,
                    requiresAuth: manifest.requiresAuth,
                    summary: manifest.summary,
                    commandCount: manifest.commands.filter { !$0.path.isEmpty }.count,
                    formats: manifest.formats,
                    commands: manifest.commands.filter { !$0.path.isEmpty }
                )
            }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return ToolIndex(
            generated: generated.map(formatter.string(from:)),
            toolCount: entries.count,
            commandCount: entries.reduce(0) { $0 + $1.commandCount },
            tools: entries
        )
    }

    /// Encodes the index as stable, human-diffable JSON.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

// MARK: - Text Rendering

extension ToolIndex: TextRenderable {

    public func renderText() -> String {
        var lines = ["\(toolCount) tools · \(commandCount) commands"]
        if let generated { lines.append("generated \(generated)") }
        lines.append("")

        let width = tools.map(\.tool.count).max() ?? 0
        for tool in tools {
            let name = tool.tool.padding(toLength: width, withPad: " ", startingAt: 0)
            let auth = tool.requiresAuth ? " [needs credentials]" : ""
            lines.append("  \(name)  \(tool.version)  \(tool.summary ?? "")\(auth)")
        }
        return lines.joined(separator: "\n")
    }
}
