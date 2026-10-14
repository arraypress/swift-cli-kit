//
//  LineSplitter.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Turns the chunks a pipe delivers into whole lines. A chunk ends wherever
//  the kernel's buffer did, not where a line did, so a line — or one UTF-8
//  character — can arrive in two halves; only complete lines are decoded.
//
//  `\n`, `\r\n` and a lone `\r` all end a line. The last is what progress
//  bars write (tqdm, curl, ffmpeg redraw one line with `\r`), and `\r\n` must
//  be ONE ending: Swift treats CRLF as a single grapheme, and splitting text
//  on `\n` alone has already cost this fleet two silent bugs.
//

import Foundation

/// Splits a byte stream into lines, one chunk at a time.
struct LineSplitter: Sendable {

    /// Bytes of a line that has not ended yet.
    private var pending = Data()

    /// The last byte fed was `\r`: a `\n` arriving next belongs to it.
    private var afterCarriageReturn = false

    /// Feeds one chunk and returns the lines it completed, in order.
    mutating func feed(_ chunk: Data) -> [String] {
        var lines: [String] = []
        var start = chunk.startIndex
        var index = chunk.startIndex
        while index < chunk.endIndex {
            let byte = chunk[index]
            if afterCarriageReturn {
                afterCarriageReturn = false
                if byte == 0x0A {
                    // The `\n` of a `\r\n` whose line already ended at the `\r`.
                    index += 1
                    start = index
                    continue
                }
            }
            if byte == 0x0A || byte == 0x0D {
                lines.append(take(chunk[start..<index]))
                afterCarriageReturn = byte == 0x0D
                start = index + 1
            }
            index += 1
        }
        if start < chunk.endIndex { pending.append(chunk[start..<chunk.endIndex]) }
        return lines
    }

    /// The unterminated last line, if the stream ended inside one.
    mutating func finish() -> String? {
        afterCarriageReturn = false
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }

    /// The pending bytes plus `tail`, as one line, leaving nothing pending.
    private mutating func take(_ tail: Data) -> String {
        guard !pending.isEmpty else { return String(decoding: tail, as: UTF8.self) }
        pending.append(tail)
        defer { pending.removeAll(keepingCapacity: true) }
        return String(decoding: pending, as: UTF8.self)
    }
}
