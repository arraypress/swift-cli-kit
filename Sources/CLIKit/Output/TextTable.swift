//
//  TextTable.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Column-aligned plain text for people reading a terminal.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Lays rows out in aligned columns, fitted to the terminal.
public enum TextTable {

    /// Assumed width when stdout is not a terminal or reports nothing useful.
    static let fallbackWidth = 100

    /// The terminal's column count.
    public static var terminalWidth: Int {
        var size = winsize()
        if ioctl(FileHandle.standardOutput.fileDescriptor, TIOCGWINSZ, &size) == 0, size.ws_col > 20 {
            return Int(size.ws_col)
        }
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"], let value = Int(columns), value > 20 {
            return value
        }
        return fallbackWidth
    }

    /// Renders a header row and body, aligned and fitted to `width`.
    ///
    /// - Parameters:
    ///   - columns: Header labels.
    ///   - rows: One array of cells per row.
    ///   - flexible: Indices that may be shortened.
    ///   - width: Available columns.
    public static func render(
        columns: [String],
        rows: [[String]],
        flexible: [Int]? = nil,
        width: Int = terminalWidth
    ) -> String {
        guard !columns.isEmpty else { return "" }

        // A cell containing a newline would break the grid; fold them.
        let body = rows.map { row in
            (0..<columns.count).map { index in
                index < row.count ? flatten(row[index]) : ""
            }
        }

        var widths = columns.indices.map { index in
            max(displayWidth(columns[index]), body.map { displayWidth($0[index]) }.max() ?? 0)
        }

        let gutter = 2
        let separators = gutter * max(0, columns.count - 1)
        var total = widths.reduce(0, +) + separators

        // Shrink the widest flexible column repeatedly rather than scaling all
        // of them: one long title should give up its space, not every column.
        let shrinkable = Set(flexible ?? Array(columns.indices))
        while total > width {
            guard let victim = widths.indices
                .filter({ shrinkable.contains($0) && widths[$0] > 8 })
                .max(by: { widths[$0] < widths[$1] })
            else { break }

            let excess = total - width
            widths[victim] = max(8, widths[victim] - max(1, excess))
            total = widths.reduce(0, +) + separators
        }

        var lines: [String] = []
        lines.append(rowText(columns, widths: widths, gutter: gutter))
        lines.append(widths.map { String(repeating: "─", count: $0) }.joined(separator: String(repeating: " ", count: gutter)))
        for row in body {
            lines.append(rowText(row, widths: widths, gutter: gutter))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func rowText(_ cells: [String], widths: [Int], gutter: Int) -> String {
        cells.indices
            .map { pad(truncate(cells[$0], to: widths[$0]), to: widths[$0]) }
            .joined(separator: String(repeating: " ", count: gutter))
            // A padded final column leaves invisible trailing spaces on a line
            // someone may well copy.
            .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    private static func flatten(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    static func truncate(_ value: String, to width: Int) -> String {
        guard displayWidth(value) > width, width > 1 else { return value }
        var result = ""
        var used = 0
        for character in value {
            let size = displayWidth(String(character))
            if used + size > width - 1 { break }
            result.append(character)
            used += size
        }
        return result + "…"
    }

    private static func pad(_ value: String, to width: Int) -> String {
        let deficit = width - displayWidth(value)
        return deficit > 0 ? value + String(repeating: " ", count: deficit) : value
    }

    /// Column count a string occupies.
    ///
    /// Emoji and CJK take two cells; counting characters would leave every row
    /// after one misaligned, which is a very common way terminal tables go wrong.
    static func displayWidth(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { total, scalar in
            total + (isWide(scalar) ? 2 : (scalar.properties.isVariationSelector ? 0 : 1))
        }
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,      // Hangul Jamo
             0x2E80...0xA4CF,      // CJK radicals … Yi
             0xAC00...0xD7A3,      // Hangul syllables
             0xF900...0xFAFF,      // CJK compatibility ideographs
             0xFE30...0xFE6F,      // CJK compatibility forms
             0xFF00...0xFF60,      // Fullwidth forms
             0xFFE0...0xFFE6,
             0x1F300...0x1F64F,    // Emoji
             0x1F680...0x1F6FF,    // Transport and map symbols (🚀 🚗 ✈)
             0x1F900...0x1F9FF,
             0x1FA70...0x1FAFF:
            return true
        default:
            // Regional indicators are deliberately narrow: a flag is a *pair*
            // of them rendered in 2 cells, so 1 + 1 lands on the right total.
            return false
        }
    }
}
