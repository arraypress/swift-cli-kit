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
//     half-overwritten bar.
//
//  3. **But redirected is not the same as silent.** For a long time rule 2 was
//     implemented as "produce nothing at all", and that turned out to be the
//     worse failure: a tool in a long silent phase is byte-for-byte
//     indistinguishable from a tool that has hung. `transcribe` looked frozen
//     for ten minutes while a speech model installed, because stderr was a
//     pipe. So `enabled` now says WHETHER to report, and the terminal decides
//     HOW: a redrawn bar for a person, one line per phase change for a log.
//

import Foundation

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

    /// Whether a redrawn bar is possible — stderr is a terminal and the caller
    /// wants output.
    private let drawing: Bool

    /// Whether phase changes are announced as plain lines when drawing is off.
    private let announcePhases: Bool

    /// The last phase announced, so only a CHANGE writes a line.
    private var lastAnnounced: String?

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
    ///   - enabled: Whether to report progress AT ALL. `false` is `--quiet`
    ///     and means silence. `true` or `nil` mean "report", and the medium is
    ///     chosen from the terminal: a redrawn bar when stderr is a TTY, one
    ///     plain line per phase change when it is not.
    ///
    ///     Note what this is NOT: passing `true` does not force a bar into a
    ///     pipe. Nobody wants carriage returns in a log, so that decision
    ///     stays with the terminal and only the question "say anything?" is
    ///     the caller's. The older reading — `enabled: !quiet &&
    ///     stderrIsTTY` — collapsed the two questions into one and made every
    ///     piped run mute.
    public convenience init(label: String, enabled: Bool? = nil) {
        let wanted = enabled ?? true
        self.init(label: label,
                  drawing: wanted && Terminal.stderrIsTTY,
                  announcing: wanted && !Terminal.stderrIsTTY)
    }

    /// The designated initialiser, with both decisions already made.
    ///
    /// Internal because the public API deliberately does not let a caller draw
    /// a bar into a pipe. The test suite runs with stderr redirected, so
    /// without this seam the drawing path could not be exercised at all — and
    /// a redraw that nobody tests is a redraw that smears the day someone
    /// resizes their window.
    init(label: String, drawing: Bool, announcing: Bool) {
        self.label = label
        self.drawing = drawing
        self.announcePhases = announcing
    }

    // MARK: Drawing

    /// Redraws at the given fraction (0–1).
    ///
    /// Rounded to whole percent before comparing, so a callback firing hundreds
    /// of times a second still only redraws a hundred times.
    public func update(_ fraction: Double, label: String? = nil) {
        guard drawing else {
            announce(label)
            return
        }

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

        if drawing { clear() }
        if let message { Terminal.writeError(message) }
    }

    /// Removes the bar without printing anything, for a caller about to write
    /// its own error.
    public func clearLine() {
        lock.lock()
        defer { lock.unlock() }
        if drawing { clear() }
    }

    /// Writes one line for a phase the caller has just entered.
    ///
    /// Only on a CHANGE: the callback behind this fires hundreds of times a
    /// second and the point is a legible log, not a flood.
    private func announce(_ label: String?) {
        guard announcePhases else { return }

        lock.lock()
        defer { lock.unlock() }

        // Falls back to the label the bar was CREATED with. Most tools name
        // the work once and then push bare fractions — `dupe` says "scanning"
        // at construction and never again — so keying announcements strictly
        // to a new label meant the commonest shape in the fleet announced
        // nothing at all. The bar's label is the phase; a change of label is
        // a change of phase.
        let phase = label ?? self.label
        guard !phase.isEmpty, phase != lastAnnounced else { return }
        lastAnnounced = phase
        if let label { self.label = label }
        Terminal.writeError(phase + "…")
    }

    // MARK: Internals

    private func draw(percent: Int) {
        let width = TextTable.width(of: FileHandle.standardError.fileDescriptor)

        // Reserve room for the label, the percentage and the brackets; the bar
        // takes what is left, and disappears entirely on a very narrow window
        // rather than wrapping onto a second line it cannot then erase.
        // Measured in display cells, not characters: an emoji in the label
        // occupies two, and counting it as one leaves a smear un-erased.
        let suffix = String(format: "%3d%%", percent)
        let fixed = TextTable.displayWidth(label) + suffix.count + 4
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
        let cells = TextTable.displayWidth(line)
        let padding = max(0, lastWidth - cells)
        lastWidth = cells

        FileHandle.standardError.write(Data(("\r" + line + String(repeating: " ", count: padding)).utf8))
    }

    private func clear() {
        guard lastWidth > 0 else { return }
        FileHandle.standardError.write(Data(("\r" + String(repeating: " ", count: lastWidth) + "\r").utf8))
        lastWidth = 0
        lastDrawn = -1
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
