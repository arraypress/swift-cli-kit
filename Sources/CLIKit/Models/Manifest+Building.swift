//
//  Manifest+Building.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Building a manifest from a tool's own command tree, and showing it.
//

import ArgumentParser
import Foundation

extension Manifest {

    /// Builds the manifest for a tool from its own command tree.
    static func forTool<Root: ParsableCommand & ServiceProviding>(_ root: Root.Type) throws -> Manifest {
        try Manifest.build(
            dumpHelpJSON: try SelfInvocation.dumpHelp(),
            service: Root.service.id,
            requiresAuth: Root.service.credentials.contains { $0.isRequired },
            version: Root.configuration.version.nilIfBlank ?? "0.0.0",
            effects: CommandEffects.table(for: Root.self)
        )
    }
}

// MARK: - Text Rendering

extension Manifest: TextRenderable {

    public func renderText() -> String {
        var lines = ["\(tool) \(version) — \(service)\(requiresAuth ? " (credentials required)" : "")"]
        lines.append("")

        let width = commands.map(\.invocation.count).max() ?? 0
        let tags = commands.map { $0.effect.map(Self.tag) ?? "" }
        let tagWidth = tags.map(\.count).max() ?? 0
        for (command, tag) in zip(commands, tags) where !command.path.isEmpty {
            let padded = command.invocation.padding(toLength: width, withPad: " ", startingAt: 0)
            let label = tagWidth == 0 ? "" : tag.padding(toLength: tagWidth, withPad: " ", startingAt: 0) + "  "
            lines.append("  \(padded)  \(label)\(command.summary ?? "")")
        }

        lines.append("")
        lines.append("Formats: \(formats.joined(separator: ", "))")
        if let safety {
            lines.append("Read-only: \(safety.readOnlyFlag) or \(safety.readOnlyEnvironment)=1 refuses every command not marked [reads]")
            lines.append("Untrusted text: \(safety.untrustedMarker), \(safety.untrustedDefault)")
        }
        lines.append("Exit codes: " + exitCodes.keys.sorted().map { "\($0)=\(exitCodes[$0] ?? "")" }
            .joined(separator: ", "))
        return lines.joined(separator: "\n")
    }

    /// The short label `describe` puts beside a command.
    static func tag(_ effect: CommandEffect) -> String {
        switch effect.kind {
        case .readOnly: "[reads]"
        case .acting: effect.destructive ? "[acts, destructive]" : "[acts]"
        case .undeclared: "[undeclared]"
        }
    }
}
