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
            version: Root.configuration.version.nilIfEmpty ?? "0.0.0"
        )
    }
}

// MARK: - Text Rendering

extension Manifest: TextRenderable {

    public func renderText() -> String {
        var lines = ["\(tool) \(version) — \(service)\(requiresAuth ? " (credentials required)" : "")"]
        lines.append("")

        let width = commands.map(\.invocation.count).max() ?? 0
        for command in commands where !command.path.isEmpty {
            let padded = command.invocation.padding(toLength: width, withPad: " ", startingAt: 0)
            lines.append("  \(padded)  \(command.summary ?? "")")
        }

        lines.append("")
        lines.append("Formats: \(formats.joined(separator: ", "))")
        lines.append("Exit codes: " + exitCodes.keys.sorted().map { "\($0)=\(exitCodes[$0] ?? "")" }
            .joined(separator: ", "))
        return lines.joined(separator: "\n")
    }
}
