//
//  Terminal.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  stdout, stderr, and telling a person from a pipe.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
        write(Data(string.utf8))
    }

    /// Writes bytes to standard output.
    public static func write(_ data: Data) {
        write(data, to: FileHandle.standardOutput.fileDescriptor, brokenPipeEndsRun: true)
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
        write(Data((string + "\n").utf8), to: FileHandle.standardError.fileDescriptor,
              brokenPipeEndsRun: false)
    }

    /// The raw write, restarted across signals and partial writes.
    ///
    /// A closed stdout — `tool … | head -1` after head has what it wants — is
    /// how a pipeline says "enough", not a failure: the run ends cleanly with
    /// exit 0, the good-citizen behaviour `head` expects. That needs SIGPIPE
    /// ignored (``CLIRunner`` does) so the write returns `EPIPE` instead of
    /// killing the process at 141, outside the documented exit codes.
    /// `FileHandle.write` would raise an uncatchable exception here instead.
    ///
    /// A closed stderr never ends the run — losing a diagnostic is not a
    /// reason to abandon the payload.
    private static func write(_ data: Data, to descriptor: Int32, brokenPipeEndsRun: Bool) {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard var base = buffer.baseAddress else { return }
            var remaining = buffer.count

            while remaining > 0 {
                let written = systemWrite(descriptor, base, remaining)
                if written > 0 {
                    base += written
                    remaining -= written
                    continue
                }
                if errno == EINTR { continue }
                if errno == EPIPE, brokenPipeEndsRun { exit(CLIExitCode.ok.rawValue) }
                return
            }
        }
    }
}

/// The libc `write`, named so the enum's own overloads cannot shadow it.
private func systemWrite(_ descriptor: Int32, _ base: UnsafeRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.write(descriptor, base, count)
    #else
    Glibc.write(descriptor, base, count)
    #endif
}
