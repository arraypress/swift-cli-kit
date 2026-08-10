//
//  Manifest.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A machine-readable description of a tool's command tree.
//
//  Derived from ArgumentParser's own `--experimental-dump-help` output rather
//  than hand-written, so it cannot drift from the commands that actually exist.
//  Hand-maintained manifests are wrong the first time someone adds a flag.
//

import Foundation

// MARK: - Manifest

/// Everything an automated caller needs to drive a tool without reading `--help`.
public struct Manifest: Codable, Sendable {

    // MARK: Argument

    /// One argument of one command.
    public struct Argument: Codable, Sendable {

        /// `positional`, `option`, or `flag`.
        public let kind: String

        /// The name as typed: `"query"` for a positional, `"--limit"` otherwise.
        public let name: String

        /// A short alias such as `"-n"`, when one exists.
        public let short: String?

        /// Whether the command fails without it.
        public let required: Bool

        /// Whether it accepts several values.
        public let repeating: Bool

        /// The help text.
        public let summary: String?

        /// The value used when the argument is omitted.
        public let defaultValue: String?

        /// The permitted values, for enumerated options.
        public let values: [String]?
    }

    // MARK: Command

    /// One invocable command.
    public struct Command: Codable, Sendable {

        /// The subcommand path, e.g. `["channel", "videos"]`. Empty for the root.
        public let path: [String]

        /// The full invocation, e.g. `"yt-fetch channel videos"`.
        public let invocation: String

        public let summary: String?
        public let details: String?
        public let arguments: [Argument]
    }

    // MARK: Properties

    /// The binary name.
    public let tool: String

    /// The tool's own one-line abstract.
    ///
    /// Taken from the root command whether or not that root is *invocable*. A
    /// tool that only dispatches to subcommands has no entry in ``commands``,
    /// and inferring its description from the first subcommand instead
    /// misreports it — yt-fetch was summarised as "Search YouTube." because
    /// `search` happened to be listed first.
    public let summary: String?

    /// The root command's longer discussion, when it has one.
    public let details: String?

    /// The tool's version.
    public let version: String

    /// The service it talks to, e.g. `"youtube"`.
    public let service: String

    /// Whether any credential is required before it will work.
    public let requiresAuth: Bool

    /// Output formats accepted by `--<format>`.
    public let formats: [String]

    /// Exit code → meaning.
    public let exitCodes: [String: String]

    /// Every leaf command, flattened.
    ///
    /// Flattened rather than nested: a caller wanting to know how to invoke
    /// something should not have to walk a tree to find it.
    public let commands: [Command]
}

// MARK: - Building

public extension Manifest {

    /// Builds a manifest from ArgumentParser's `--experimental-dump-help` JSON.
    ///
    /// - Parameters:
    ///   - dumpHelpJSON: The raw bytes of that command's output.
    ///   - service: The service identifier from the tool's ``ServiceSpec``.
    ///   - requiresAuth: Whether a credential is mandatory.
    ///   - version: The tool version.
    /// - Throws: A ``CLIError`` if the JSON cannot be understood.
    static func build(
        dumpHelpJSON: Data,
        service: String,
        requiresAuth: Bool,
        version: String
    ) throws -> Manifest {
        let dump: ToolInfo
        do {
            dump = try JSONDecoder().decode(ToolInfo.self, from: dumpHelpJSON)
        } catch {
            throw CLIError.parseFailure("Could not decode the command tree: \(error)")
        }

        var commands: [Manifest.Command] = []
        flatten(dump.command, root: dump.command.commandName, path: [], into: &commands)

        return Manifest(
            tool: dump.command.commandName,
            summary: dump.command.abstract?.nilIfEmpty,
            details: dump.command.discussion?.nilIfEmpty,
            version: version,
            service: service,
            requiresAuth: requiresAuth,
            formats: OutputFormat.allCases.map(\.rawValue),
            exitCodes: Dictionary(
                uniqueKeysWithValues: CLIExitCode.allCases.map {
                    (String($0.rawValue), describe($0))
                }
            ),
            commands: commands
        )
    }

    /// Walks the command tree depth-first, recording every node that can be run.
    private static func flatten(
        _ node: ToolInfo.CommandInfo,
        root: String,
        path: [String],
        into commands: inout [Manifest.Command]
    ) {
        let children = (node.subcommands ?? []).filter {
            // `help` is ArgumentParser's own; it is not part of the tool's API.
            $0.shouldDisplay != false && $0.commandName != "help"
        }

        // A group that only dispatches to children is not itself invocable,
        // unless it declares a default subcommand.
        let isInvocable = children.isEmpty || node.defaultSubcommand != nil

        if isInvocable {
            commands.append(
                Manifest.Command(
                    path: path,
                    invocation: ([root] + path).joined(separator: " "),
                    summary: node.abstract?.nilIfEmpty,
                    details: node.discussion?.nilIfEmpty,
                    arguments: (node.arguments ?? [])
                        .filter { $0.shouldDisplay != false }
                        .compactMap(Manifest.Argument.init)
                        // `--help` and `--version` are ArgumentParser's, not the
                        // tool's. Listing them invites a caller to "invoke" help
                        // instead of doing the work it meant to do.
                        .filter { !Manifest.reservedArguments.contains($0.name) }
                )
            )
        }

        for child in children {
            flatten(child, root: root, path: path + [child.commandName], into: &commands)
        }
    }

    /// Arguments supplied by the parser rather than the tool.
    static let reservedArguments: Set<String> = ["--help", "--version"]

    /// Flags that choose an output format.
    ///
    /// Meaningful on a command line, meaningless over MCP — that transport
    /// always wants the piped default, and offering `--text` invites an agent to
    /// ask for prose it then has to parse.
    static let formatArguments: Set<String> = ["--json", "--text", "--ndjson", "--csv", "--markdown"]

    /// One-line meaning for each exit code, so the manifest is self-describing.
    private static func describe(_ code: CLIExitCode) -> String {
        switch code {
        case .ok: return "success"
        case .notFound: return "the resource does not exist; do not retry"
        case .usage: return "invalid arguments; fix the invocation"
        case .authRequired: return "a credential is missing; see the error hint"
        case .rateLimited: return "throttled; back off and retry"
        case .upstream: return "network or upstream failure; retry later"
        case .parseFailure: return "the extractor is out of date; upgrade the tool"
        }
    }
}

// MARK: - Argument Mapping

extension Manifest.Argument {

    init?(_ info: ToolInfo.ArgumentInfo) {
        let long = info.names?.first { $0.kind == "long" }?.name
        let short = info.names?.first { $0.kind == "short" }?.name

        switch info.kind {
        case "positional":
            guard let valueName = info.valueName else { return nil }
            self.name = valueName
            self.short = nil
        default:
            guard let long else { return nil }
            self.name = "--\(long)"
            self.short = short.map { "-\($0)" }
        }

        self.kind = info.kind
        self.required = !(info.isOptional ?? true)
        self.repeating = info.isRepeating ?? false
        self.summary = info.abstract?.nilIfEmpty
        self.defaultValue = info.defaultValue?.nilIfEmpty

        // Falls back to scraping "(values: a, b)" out of help text for builds
        // that record the choices nowhere structured.
        self.values = info.permittedValues
            ?? Manifest.Argument.parseValues(from: info.abstract)
    }

    /// Extracts `a, b, c` from a trailing `(values: a, b, c)` in help text.
    static func parseValues(from abstract: String?) -> [String]? {
        guard let abstract,
              let open = abstract.range(of: "(values: "),
              let close = abstract.range(of: ")", range: open.upperBound..<abstract.endIndex)
        else { return nil }

        let list = abstract[open.upperBound..<close.lowerBound]
        let values = list
            .split(separator: ";").first?              // drop a trailing "; default: x"
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []

        return values.isEmpty ? nil : values
    }
}

// MARK: - Dump Help Mirror

/// A decoding mirror of ArgumentParser's `ToolInfoV0`.
///
/// Redeclared here because `ArgumentParserToolInfo` is not a public product of
/// swift-argument-parser, so its types cannot be imported. Every field is
/// optional: this decodes output from a version we do not control, and a new
/// key must never break `describe`.
struct ToolInfo: Decodable {

    struct NameInfo: Decodable {
        let kind: String?
        let name: String
    }

    /// Where a version of ArgumentParser records an option's permitted values.
    ///
    /// The key has moved between releases — `allValueStrings` in some, `allValues`
    /// in others, with `completionKind.list.values` mirroring it — so all three
    /// are read. Losing them is not cosmetic: without the permitted values an
    /// MCP client has to guess at an enum, and a guess is a failed call.
    struct CompletionKind: Decodable {
        struct ListValues: Decodable { let values: [String]? }
        let list: ListValues?
    }

    struct ArgumentInfo: Decodable {
        let kind: String
        let shouldDisplay: Bool?
        let isOptional: Bool?
        let isRepeating: Bool?
        let names: [NameInfo]?
        let valueName: String?
        let defaultValue: String?
        let allValueStrings: [String]?
        let allValues: [String]?
        let completionKind: CompletionKind?
        let abstract: String?

        /// The permitted values, from whichever key this build supplies.
        var permittedValues: [String]? {
            allValues?.nilIfEmpty
                ?? allValueStrings?.nilIfEmpty
                ?? completionKind?.list?.values?.nilIfEmpty
        }
    }

    struct CommandInfo: Decodable {
        let commandName: String
        let shouldDisplay: Bool?
        let abstract: String?
        let discussion: String?
        let defaultSubcommand: String?
        let subcommands: [CommandInfo]?
        let arguments: [ArgumentInfo]?
    }

    let command: CommandInfo
}

// MARK: - Helpers
