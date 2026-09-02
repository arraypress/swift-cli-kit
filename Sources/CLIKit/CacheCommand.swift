//
//  CacheCommand.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  `<tool> cache` — inspect or empty the on-disk cache. Beside DiskCache,
//  which it reports on.
//

import ArgumentParser
import Foundation

/// What a tool is keeping on disk.
public struct CacheReport: Encodable, TextRenderable, Sendable {

    /// Where the cache lives.
    public let location: String

    /// How many entries it holds.
    public let entries: Int

    /// How much space they take.
    public let bytes: Int

    public init(location: String, entries: Int, bytes: Int) {
        self.location = location
        self.entries = entries
        self.bytes = bytes
    }

    /// The size, in units a person reads.
    public var size: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public func renderText() -> String {
        entries == 0
            ? "Empty. \(location)"
            : "\(entries) entr\(entries == 1 ? "y" : "ies"), \(size). \(location)"
    }
}

/// `<tool> cache` — inspect or empty the on-disk cache.
///
/// Generic over the tool, like ``DescribeCommand`` and ``MCPCommand``, so a
/// tool adopts the verb rather than writing it. Twenty-eight tools had
/// hand-rolled this, 1,857 lines between them, and every copy declared only
/// `--json`: `cache info --csv` and `--text` were silently ignored across the
/// whole fleet. Taking ``CommonOptions`` here fixes that everywhere at once.
///
/// The cache namespace comes from the tool's own ``ServiceSpec``, so it cannot
/// drift from the one the tool reads and writes.
public struct CacheCommand<Root: ParsableCommand & ServiceProviding>: ParsableCommand {

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Inspect or clear this tool's cached data.",
            discussion: """
                Responses are cached on disk so a repeated question costs \
                nothing. `info` says where and how much; `clear` empties it.

                Nothing here reaches the network.
                """,
            subcommands: [Info.self, Clear.self],
            defaultSubcommand: Info.self
        )
    }

    public init() {}

    /// `<tool> cache info` — where the cache is and how big it has become.
    public struct Info: ParsableCommand {

        // Computed, not stored: a nested type inherits its parent's generic
        // parameter, and a generic type cannot hold a static stored property.
        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "info",
                abstract: "Show the cache location, entry count and size."
            )
        }

        public init() {}

        @OptionGroup public var common: CommonOptions

        public func run() throws {
            let cache = DiskCache(tool: Root.service.toolName)
            let usage = cache.usage()
            try common.emitter.emit(
                CacheReport(location: cache.directoryURL.path, entries: usage.entries, bytes: usage.bytes)
            )
        }
    }

    /// `<tool> cache clear` — throw it away.
    public struct Clear: ParsableCommand {

        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "clear",
                abstract: "Delete everything this tool has cached."
            )
        }

        public init() {}

        @OptionGroup public var common: CommonOptions

        public func run() throws {
            let cache = DiskCache(tool: Root.service.toolName)
            let usage = cache.usage()
            try cache.clear()
            // On stderr: clearing is an action, not a payload, and reporting
            // it must not corrupt a pipeline that is reading JSON.
            if !common.quiet {
                Terminal.writeError(
                    usage.entries == 0
                        ? "Cache was already empty."
                        : "Cleared \(usage.entries) cached entr\(usage.entries == 1 ? "y" : "ies")."
                )
            }
        }
    }
}
