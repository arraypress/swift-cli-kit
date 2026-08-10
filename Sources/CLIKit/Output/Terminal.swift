//
//  Terminal.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  stdout, stderr, and telling a person from a pipe.
//

import Foundation

/// Terminal capability probing and raw stream writes.
public enum Terminal {

    /// Whether standard output is attached to a terminal.
    ///
    /// This is how a tool tells a person from a pipe. It drives format
    /// selection, pretty-printing, and colour, so that neither audience has to
    /// pass a flag to get what it wants.
    public static var stdoutIsTTY: Bool {
        isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }

    /// Whether standard error is attached to a terminal.
    public static var stderrIsTTY: Bool {
        isatty(FileHandle.standardError.fileDescriptor) == 1
    }

    /// Writes to standard output. Never adds a newline.
    public static func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    /// Writes a line to standard output.
    public static func writeLine(_ string: String = "") {
        write(string + "\n")
    }

    /// Writes a line to standard error.
    ///
    /// Diagnostics, warnings and progress belong here — stdout carries the
    /// payload and nothing else, so that piping a tool's output into a parser
    /// never has to strip chatter.
    public static func writeError(_ string: String) {
        guard let data = (string + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
