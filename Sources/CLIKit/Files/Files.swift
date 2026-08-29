//
//  Files.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The three filesystem lines every tool writes, and writes with the same
//  omissions: the tilde left unexpanded, the error thrown as a bare
//  Foundation message with no exit code behind it.
//

import Foundation

/// Reading and writing the files a tool is pointed at.
///
/// Each of these expands a leading `~`, because the path came from a saved
/// profile or an MCP argument as often as from a shell, and each turns a
/// failure into a ``CLIError`` that carries the right exit code — a missing
/// input is `1`, an unwritable output is `5` — rather than whatever Foundation
/// felt like saying.
public enum Files {

    /// The contents of the file at `path`, or of standard input for `-`.
    ///
    /// `-` is the family's spelling for "what is piped in", so a tool that
    /// reads its spec this way takes `cat spec.json | tool new -` without
    /// writing that case itself.
    ///
    /// - Parameters:
    ///   - path: A file, `~` allowed, or `-`.
    ///   - service: The service for the error envelope.
    ///   - hint: What to do instead, for the envelope.
    /// - Throws: ``CLIError`` with ``CLIError/Code/notFound`` when there is
    ///   nothing readable at `path`.
    public static func read(_ path: String, service: String? = nil, hint: String? = nil) throws -> Data {
        if path == "-" { return FileHandle.standardInput.readDataToEndOfFile() }

        guard let data = FileManager.default.contents(atPath: path.expandedPath) else {
            throw CLIError.notFound("Cannot read \(path)", service: service, hint: hint)
        }
        return data
    }

    /// The directory at `path`, created with its parents if it is not there.
    ///
    /// - Returns: The directory, tilde expanded, for the caller to write into.
    /// - Throws: ``CLIError`` with ``CLIError/Code/upstream`` when it cannot
    ///   be created.
    @discardableResult
    public static func ensureDirectory(_ path: String) throws -> URL {
        try ensureDirectory(URL(fileURLWithPath: path.expandedPath, isDirectory: true))
    }

    /// The directory at `url`, created with its parents if it is not there.
    @discardableResult
    public static func ensureDirectory(_ url: URL) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw CLIError.upstream("Could not create \(url.path): \(error.localizedDescription)")
        }
        return url
    }

    /// Writes `data` to `path`, atomically, replacing what was there.
    ///
    /// Atomic so that a reader never sees half a document — and so that a
    /// failure part-way leaves the previous file, not a truncated one.
    ///
    /// - Returns: Where it was written, tilde expanded, for the summary line.
    /// - Throws: ``CLIError`` with ``CLIError/Code/upstream`` when it cannot
    ///   be written.
    @discardableResult
    public static func write(_ data: Data, to path: String) throws -> URL {
        try write(data, to: URL(fileURLWithPath: path.expandedPath))
    }

    /// Writes `data` to `url`, atomically, replacing what was there.
    @discardableResult
    public static func write(_ data: Data, to url: URL) throws -> URL {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CLIError.upstream("Could not write \(url.path): \(error.localizedDescription)")
        }
        return url
    }
}
