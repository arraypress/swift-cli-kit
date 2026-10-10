//
//  DownloadReporter.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A model download's progress on stderr: one line rewritten in place on a
//  terminal, a line per tenth when stderr is a pipe — an agent reading it
//  sees the download moving without being flooded. stdout is never touched.
//

import Foundation

/// Shows a download's progress.
final class DownloadReporter: @unchecked Sendable {

    private let service: String
    private let quiet: Bool
    private let lock = NSLock()
    private var lastTenth = -1
    private var drewInPlace = false

    init(service: String, quiet: Bool) {
        self.service = service
        self.quiet = quiet
    }

    /// Reports an announcement (no fraction) or how far along it is.
    func report(_ line: String, _ fraction: Double?) {
        guard !quiet else { return }
        lock.lock(); defer { lock.unlock() }
        guard let fraction else {
            Terminal.writeError("\(service): \(line)")
            return
        }
        let percent = Int((min(1, max(0, fraction)) * 100).rounded(.down))
        if Terminal.stderrIsTTY {
            FileHandle.standardError.write(Data("\r\(service): \(percent)%  \(line)\u{1B}[K".utf8))
            drewInPlace = true
        } else if percent / 10 > lastTenth {
            lastTenth = percent / 10
            Terminal.writeError("\(service): \(percent)%")
        }
    }

    /// Ends the in-place line.
    func finish() {
        guard !quiet else { return }
        lock.lock(); defer { lock.unlock() }
        if drewInPlace { FileHandle.standardError.write(Data("\n".utf8)) }
        Terminal.writeError("\(service): model installed")
    }
}
