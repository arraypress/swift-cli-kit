//
//  main.swift
//  agentic-index
//
//  Created by David Sherlock on 2026.
//
//  Collects every tool's `describe --json` into one index.
//

import CLIKit
import Foundation

// MARK: - Usage

let usage = """
agentic-index — merge the family's manifests into one index.

USAGE:
  agentic-index <tool>...            names or paths, resolved on PATH
  agentic-index --dir <directory>    every executable in a directory
  agentic-index <tool>... -o index.json

OPTIONS:
  -o, --output <file>   Write here instead of stdout.
  --stamp               Record the build time. Omitted by default so an
                        unchanged index stays byte-identical between runs.
  --text                Human-readable summary instead of JSON.
  -h, --help            This.

A tool that cannot be run, or does not answer `describe --json`, is reported on
stderr and skipped — one broken binary should not empty the directory.
"""

// MARK: - Arguments

var toolArguments: [String] = []
var directory: String?
var output: String?
var stamp = false
var asText = false

var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "--stamp":
        stamp = true
    case "--text":
        asText = true
    case "-o", "--output":
        guard let value = arguments.first else {
            FileHandle.standardError.write(Data("error: --output needs a path\n".utf8))
            exit(2)
        }
        output = value
        arguments.removeFirst()
    case "--dir":
        guard let value = arguments.first else {
            FileHandle.standardError.write(Data("error: --dir needs a path\n".utf8))
            exit(2)
        }
        directory = value
        arguments.removeFirst()
    default:
        toolArguments.append(argument)
    }
}

// MARK: - Discovery

/// Executables in a directory, ignoring the noise a build leaves behind.
func executables(in path: String) -> [String] {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isExecutableKey, .isDirectoryKey]
    )) ?? []

    return contents.compactMap { candidate in
        let values = try? candidate.resourceValues(forKeys: [.isExecutableKey, .isDirectoryKey])
        guard values?.isExecutable == true, values?.isDirectory != true else { return nil }
        // Bundles, dSYMs and object files sit beside binaries in a build folder.
        guard !candidate.lastPathComponent.contains(".") else { return nil }
        return candidate.path
    }.sorted()
}

let tools = directory.map(executables(in:)) ?? toolArguments

guard !tools.isEmpty else {
    FileHandle.standardError.write(Data("error: no tools given\n\n\(usage)\n".utf8))
    exit(2)
}

// MARK: - Collection

/// Runs `<tool> describe --json` and decodes the manifest.
func manifest(for tool: String) -> Manifest? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool, "describe", "--json"]

    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    do {
        try process.run()
    } catch {
        FileHandle.standardError.write(Data("warning: could not run \(tool)\n".utf8))
        return nil
    }

    // Read before waiting: a manifest larger than the pipe buffer would
    // otherwise deadlock, and some of these run to tens of kilobytes. The
    // stderr drain runs concurrently for the same reason — a chatty tool
    // filling that pipe first would stall both reads.
    let errHandle = err.fileHandleForReading
    DispatchQueue.global().async { _ = errHandle.readDataToEndOfFile() }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        FileHandle.standardError.write(
            Data("warning: \(tool) describe exited \(process.terminationStatus) — skipped\n".utf8)
        )
        return nil
    }

    do {
        return try JSONDecoder().decode(Manifest.self, from: data)
    } catch {
        FileHandle.standardError.write(
            Data("warning: \(tool) did not return a manifest — skipped\n".utf8)
        )
        return nil
    }
}

let manifests = tools.compactMap(manifest(for:))

guard !manifests.isEmpty else {
    FileHandle.standardError.write(Data("error: no tool answered `describe --json`\n".utf8))
    exit(1)
}

// MARK: - Output

// The index deduplicates by tool name; saying so here is what stops a
// doubled PATH entry looking like a tool that silently vanished.
let names = manifests.map(\.tool)
let duplicated = Set(names.filter { name in names.filter { $0 == name }.count > 1 })
if !duplicated.isEmpty {
    FileHandle.standardError.write(
        Data("warning: duplicate tools indexed once: \(duplicated.sorted().joined(separator: ", "))\n".utf8)
    )
}

let index = ToolIndex.build(from: manifests, generated: stamp ? Date() : nil)

if asText {
    print(index.renderText())
} else {
    do {
        let data = try index.encoded()
        if let output {
            try data.write(to: URL(fileURLWithPath: (output as NSString).expandingTildeInPath))
            FileHandle.standardError.write(
                Data("wrote \(output) — \(index.toolCount) tools, \(index.commandCount) commands\n".utf8)
            )
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    } catch {
        // A clean line, not a Swift crash dump: this runs in CI, and the
        // difference between the two is whether the log says what went wrong.
        FileHandle.standardError.write(
            Data("error: could not write the index: \(error.localizedDescription)\n".utf8)
        )
        exit(1)
    }
}

// Skipping some tools is a warning; skipping any is worth a distinct status so
// CI can decide whether a partial index should be published.
if manifests.count < tools.count {
    exit(CLIExitCode.upstream.rawValue)
}
