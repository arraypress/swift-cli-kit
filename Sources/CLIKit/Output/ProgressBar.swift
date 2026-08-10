//
//  ProgressBar.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A progress indicator for work that takes long enough to warrant one.
//
//  Two rules govern everything here:
//
//  1. **It writes to stderr, never stdout.** stdout carries the payload. A
//     progress bar redrawn into a pipe would corrupt the JSON a caller is
//     parsing, and the whole family's contract rests on that never happening.
//
//  2. **It draws only to a terminal.** When stderr is redirected — CI, a log
//     file, a subprocess — carriage returns produce thousands of lines of
//     half-overwritten bar. Off by default in that case; a caller who wants
//     periodic lines in a log can ask for them.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// A single-line progress bar on standard error.
///
/// ```swift
/// let bar = ProgressBar(label: "Transcribing")
/// bar.update(0.42)
/// bar.finish("Transcribed in 8.1s")
/// ```
///
/// Safe to use unconditionally: when stderr is not a terminal, every method is
/// a no-op apart from ``finish(_:)``, which still writes its summary line.
public final class ProgressBar: @unchecked Sendable {

    /// What the bar is measuring.
    private var label: String

    /// Whether drawing is possible at all.
    private let enabled: Bool

    /// The last fraction drawn, so a repeated value costs nothing.
    private var lastDrawn: Int = -1

    /// The width of the last line written, so it can be cleared exactly.
    private var lastWidth: Int = 0

    /// Serialises redraws — progress callbacks arrive off arbitrary threads.
    private let lock = NSLock()

    /// Creates a bar.
    ///
    /// - Parameters:
    ///   - label: Shown to the left of the bar.
    ///   - enabled: Defaults to "stderr is a terminal". Pass `false` for
    ///     `--quiet`.
    public init(label: String, enabled: Bool? = nil) {
        self.label = label
        self.enabled = enabled ?? Terminal.stderrIsTTY
    }

    // MARK: Drawing

    /// Redraws at the given fraction (0–1).
    ///
    /// Rounded to whole percent before comparing, so a callback firing hundreds
    /// of times a second still only redraws a hundred times.
    public func update(_ fraction: Double, label: String? = nil) {
        guard enabled else { return }

        lock.lock()
        defer { lock.unlock() }

        if let label { self.label = label }

        let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
        guard percent != lastDrawn || label != nil else { return }
        lastDrawn = percent

        draw(percent: percent)
    }

    /// Replaces the bar with a final line.
    ///
    /// Written even when drawing is disabled — the summary is the part worth
    /// keeping in a log.
    public func finish(_ message: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if enabled { clear() }
        if let message { Terminal.writeError(message) }
    }

    /// Removes the bar without printing anything, for a caller about to write
    /// its own error.
    public func clearLine() {
        lock.lock()
        defer { lock.unlock() }
        if enabled { clear() }
    }

    // MARK: Internals

    private func draw(percent: Int) {
        let width = Self.terminalWidth()

        // Reserve room for the label, the percentage and the brackets; the bar
        // takes what is left, and disappears entirely on a very narrow window
        // rather than wrapping onto a second line it cannot then erase.
        let suffix = String(format: "%3d%%", percent)
        let fixed = label.count + suffix.count + 4
        let barWidth = max(0, min(40, width - fixed))

        var line = label + " "
        if barWidth > 0 {
            let filled = Int((Double(percent) / 100 * Double(barWidth)).rounded())
            line += "["
                + String(repeating: "█", count: filled)
                + String(repeating: "░", count: barWidth - filled)
                + "] "
        }
        line += suffix

        // Pad to the previous width so a shorter line leaves no tail behind.
        let padding = max(0, lastWidth - line.count)
        lastWidth = line.count

        FileHandle.standardError.write(Data(("\r" + line + String(repeating: " ", count: padding)).utf8))
    }

    private func clear() {
        guard lastWidth > 0 else { return }
        FileHandle.standardError.write(Data(("\r" + String(repeating: " ", count: lastWidth) + "\r").utf8))
        lastWidth = 0
        lastDrawn = -1
    }

    /// The terminal's column count, or a conservative default.
    static func terminalWidth(fallback: Int = 80) -> Int {
        #if canImport(Darwin)
        var size = winsize()
        if ioctl(FileHandle.standardError.fileDescriptor, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        #endif
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"], let value = Int(columns), value > 0 {
            return value
        }
        return fallback
    }
}

// MARK: - Byte formatting

public extension ProgressBar {

    /// A download label with the size in it, e.g. `Whisper large-v3 (3.1 GB)`.
    ///
    /// Announcing the size matters: a model download is measured in gigabytes,
    /// and a tool that starts one without saying so is taking a decision that
    /// belongs to whoever is paying for the bandwidth.
    static func downloadLabel(_ name: String, megabytes: Int?) -> String {
        guard let megabytes, megabytes > 0 else { return name }
        let bytes = Int64(megabytes) * 1_000_000
        return "\(name) (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
    }
}
