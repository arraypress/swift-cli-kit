//
//  ProgressBarTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest

@testable import CLIKit

final class ProgressBarTests: XCTestCase {

    /// Captures stderr while the body runs.
    private func capturingStderr(_ body: () -> Void) -> String {
        let pipe = Pipe()
        let saved = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        body()

        fflush(stderr)
        dup2(saved, STDERR_FILENO)
        close(saved)
        try? pipe.fileHandleForWriting.close()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func testDisabledBarDrawsNothing() {
        // The case that matters: piped stderr must not receive thousands of
        // carriage returns. Redirected output means disabled by default.
        let output = capturingStderr {
            let bar = ProgressBar(label: "Working", enabled: false)
            for step in 0...100 { bar.update(Double(step) / 100) }
            bar.finish()
        }
        XCTAssertTrue(output.isEmpty, "drew: \(output.debugDescription)")
    }

    func testFinishMessageSurvivesEvenWhenDisabled() {
        // The summary is the part worth keeping in a log.
        let output = capturingStderr {
            ProgressBar(label: "Working", enabled: false).finish("Done in 3s")
        }
        XCTAssertEqual(output, "Done in 3s\n")
    }

    func testEnabledBarWritesToStderrNotStdout() {
        let output = capturingStderr {
            let bar = ProgressBar(label: "Working", drawing: true, announcing: false)
            bar.update(0.5)
            bar.clearLine()
        }
        XCTAssertTrue(output.contains("50%"), output.debugDescription)
        XCTAssertTrue(output.contains("\r"), "a bar redraws in place")
    }

    func testRepeatedFractionsDoNotRedraw() {
        // A progress callback can fire hundreds of times a second; only whole
        // percent changes are worth a redraw.
        let output = capturingStderr {
            let bar = ProgressBar(label: "W", drawing: true, announcing: false)
            for _ in 0..<200 { bar.update(0.42) }
            bar.clearLine()
        }
        XCTAssertEqual(output.components(separatedBy: "42%").count - 1, 1)
    }

    func testProgressIsClampedToRange() {
        let output = capturingStderr {
            let bar = ProgressBar(label: "W", drawing: true, announcing: false)
            bar.update(-5)
            bar.update(99)
            bar.clearLine()
        }
        XCTAssertTrue(output.contains("0%"))
        XCTAssertTrue(output.contains("100%"))
    }

    // MARK: Phase announcements

    // These run under `swift test`, where stderr is NOT a terminal — which is
    // exactly the case the rework is about.

    func testAPipedRunReportsPhasesInsteadOfNothing() {
        // The bug: this used to emit zero bytes, which is what a hung process
        // emits too.
        let output = capturingStderr {
            let bar = ProgressBar(label: "start")
            bar.update(0, label: "Installing model")
            bar.update(0.5, label: "Transcribing")
        }
        XCTAssertTrue(output.contains("Installing model…"), output)
        XCTAssertTrue(output.contains("Transcribing…"), output)
    }

    func testQuietIsStillSilent() {
        // `enabled: false` is --quiet and must mean nothing at all, in any
        // medium. The whole rework is worthless if it makes --quiet chatty.
        let output = capturingStderr {
            let bar = ProgressBar(label: "start", enabled: false)
            bar.update(0, label: "Installing model")
            bar.update(0.5, label: "Transcribing")
        }
        XCTAssertEqual(output, "")
    }

    func testEnabledTrueDoesNotForceABarIntoAPipe() {
        // Passing `true` says "report", not "draw". Carriage returns in a log
        // are the thing rule 2 exists to prevent, and a caller asking for
        // output should not be able to ask for that by accident.
        let output = capturingStderr {
            let bar = ProgressBar(label: "start", enabled: true)
            bar.update(0.5, label: "Transcribing")
        }
        XCTAssertFalse(output.contains("\r"), output)
        XCTAssertTrue(output.contains("Transcribing…"), output)
    }

    func testOnlyAChangeAnnounces() {
        // The callback behind this fires hundreds of times a second; the point
        // is a legible log, not a flood.
        let output = capturingStderr {
            let bar = ProgressBar(label: "start")
            for step in 0...100 {
                bar.update(Double(step) / 100, label: "Transcribing")
            }
        }
        XCTAssertEqual(output.components(separatedBy: "Transcribing").count - 1, 1, output)
    }

    func testBareFractionsAnnounceTheBarsOwnLabelOnce() {
        // The commonest shape in the fleet: name the work at construction,
        // then push bare fractions. `dupe` says "scanning" once and never
        // again. Keying announcements strictly to a NEW label meant those
        // tools stayed completely silent in a log, which is the bug this
        // whole change exists to fix — so the bar's own label is the phase.
        let output = capturingStderr {
            let bar = ProgressBar(label: "scanning")
            bar.update(0.1)
            bar.update(0.5)
            bar.update(0.9)
        }
        XCTAssertEqual(output.components(separatedBy: "scanning").count - 1, 1, output)
    }

    func testAnUnlabelledBarStaysSilent() {
        // Nothing to name, nothing to say.
        let output = capturingStderr {
            let bar = ProgressBar(label: "")
            bar.update(0.1)
        }
        XCTAssertEqual(output, "")
    }

    func testDownloadLabelStatesTheSize() {
        // A multi-gigabyte download should never begin unannounced.
        XCTAssertEqual(ProgressBar.downloadLabel("large-v3", megabytes: 3_090), "large-v3 (3.09 GB)")
        XCTAssertEqual(ProgressBar.downloadLabel("tiny", megabytes: nil), "tiny")
        XCTAssertEqual(ProgressBar.downloadLabel("auto", megabytes: 0), "auto")
    }

    func testTerminalWidthHasASaneFallback() {
        // The bar shares TextTable's probe rather than carrying its own; a
        // descriptor that is not a terminal must still yield a usable width.
        XCTAssertGreaterThan(TextTable.width(of: FileHandle.standardError.fileDescriptor), 0)
    }
}
