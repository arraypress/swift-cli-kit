//
//  DescribeCommand.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  `<tool> describe` — the machine-readable command manifest.
//

import ArgumentParser
import Foundation

/// `<tool> describe` — emit a machine-readable description of the command tree.
public struct DescribeCommand<Root: ParsableCommand & ServiceProviding>: ParsableCommand {

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "describe",
            abstract: "Describe this tool's commands in machine-readable form.",
            discussion: """
                Emits every invocable command, its arguments, permitted values, \
                defaults, output formats and exit codes — derived from the \
                command tree itself, so it cannot fall out of date.

                Intended for automated callers that would otherwise have to parse \
                --help.
                """
        )
    }

    public init() {}

    @Flag(name: .long, help: "Force JSON output (the default when piped).")
    var json: Bool = false

    public func run() throws {
        let manifest = try Manifest.forTool(Root.self)
        let format: OutputFormat = json ? .json : OutputFormat.resolve(explicit: nil)
        try Emitter(format: format).emit(manifest)
    }
}
