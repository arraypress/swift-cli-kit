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
import os

/// Shows a download's progress.
final class DownloadReporter: Sendable {

    /// What has been drawn so far — the lock also serialises the writes, so
    /// progress from several files never interleaves mid-line.
    private struct Drawn {
        var lastTenth = -1
        var inPlace = false
    }

    private let service: String
    private let quiet: Bool
    private let done: String
    private let drawn = OSAllocatedUnfairLock(initialState: Drawn())

    init(service: String, quiet: Bool, done: String = "model installed") {
        self.service = service
        self.quiet = quiet
        self.done = done
    }

    /// Reports an announcement (no fraction) or how far along it is.
    func report(_ line: String, _ fraction: Double?) {
        guard !quiet else { return }
        let service = service
        drawn.withLock { drawn in
            guard let fraction else {
                Terminal.writeError("\(service): \(line)")
                return
            }
            let percent = Int((min(1, max(0, fraction)) * 100).rounded(.down))
            if Terminal.stderrIsTTY {
                FileHandle.standardError.write(Data("\r\(service): \(percent)%  \(line)\u{1B}[K".utf8))
                drawn.inPlace = true
            } else if percent / 10 > drawn.lastTenth {
                drawn.lastTenth = percent / 10
                Terminal.writeError("\(service): \(percent)%")
            }
        }
    }

    /// Ends the in-place line.
    func finish() {
        guard !quiet else { return }
        let service = service, done = done
        drawn.withLock { drawn in
            if drawn.inPlace { FileHandle.standardError.write(Data("\n".utf8)) }
            Terminal.writeError("\(service): \(done)")
        }
    }
}
