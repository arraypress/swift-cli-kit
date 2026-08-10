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
            let bar = ProgressBar(label: "Working", enabled: true)
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
            let bar = ProgressBar(label: "W", enabled: true)
            for _ in 0..<200 { bar.update(0.42) }
            bar.clearLine()
        }
        XCTAssertEqual(output.components(separatedBy: "42%").count - 1, 1)
    }

    func testProgressIsClampedToRange() {
        let output = capturingStderr {
            let bar = ProgressBar(label: "W", enabled: true)
            bar.update(-5)
            bar.update(99)
            bar.clearLine()
        }
        XCTAssertTrue(output.contains("0%"))
        XCTAssertTrue(output.contains("100%"))
    }

    func testDownloadLabelStatesTheSize() {
        // A multi-gigabyte download should never begin unannounced.
        XCTAssertEqual(ProgressBar.downloadLabel("large-v3", megabytes: 3_090), "large-v3 (3.09 GB)")
        XCTAssertEqual(ProgressBar.downloadLabel("tiny", megabytes: nil), "tiny")
        XCTAssertEqual(ProgressBar.downloadLabel("auto", megabytes: 0), "auto")
    }

    func testTerminalWidthHasASaneFallback() {
        XCTAssertGreaterThan(ProgressBar.terminalWidth(fallback: 80), 0)
    }
}
