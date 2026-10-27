//
//  OutFileTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The bug under test: `-o short.mp4` on a run that wrote several clips put
//  every clip in short.mp4, each over the last, and exited 0. Each rule has a
//  test that fails when the rule is broken.
//

import XCTest
@testable import CLIKit

final class OutFileTests: XCTestCase {

    // MARK: - What is refused

    func testOneFileNameForSeveralResultsIsRefusedWithAFolderToTypeInstead() {
        XCTAssertEqual(
            OutFile.problem("renders/short.mp4", results: 3, isFolder: false),
            "-o short.mp4 names one file, but this run writes 3: give -o a folder (-o short) and each file lands inside it."
        )
    }

    func testTwoResultsAreAlreadyTooMany() {
        XCTAssertNotNil(OutFile.problem("a.srt", results: 2, isFolder: false))
    }

    func testTheFolderOptionIsNamedWhenItIsAnotherOption() {
        XCTAssertEqual(
            OutFile.problem("chart.png", results: 4, isFolder: false, option: "--output", folderOption: "--out"),
            "--output chart.png names one file, but this run writes 4: give --out a folder (--out chart) and each file lands inside it."
        )
    }

    func testTheExtensionIsMatchedWhateverItsCase() {
        XCTAssertNotNil(OutFile.problem("Short.MP4", results: 2, isFolder: false))
    }

    // MARK: - What is accepted

    func testOneResultMayHaveAFileName() {
        XCTAssertNil(OutFile.problem("short.mp4", results: 1, isFolder: false))
        XCTAssertNil(OutFile.problem("short.mp4", results: 0, isFolder: false))
    }

    func testAFolderNameTakesAnyNumberOfResults() {
        XCTAssertNil(OutFile.problem("clips", results: 9, isFolder: false))
        XCTAssertNil(OutFile.problem("build/v1.2", results: 9, isFolder: false))
    }

    func testAnExistingFolderTakesAnyNumberWhateverItIsCalled() {
        XCTAssertNil(OutFile.problem("clips.mp4", results: 9, isFolder: true))
    }

    func testTheCallersOwnExtensionsReplaceTheDefaults() {
        XCTAssertNil(OutFile.problem("a.mp4", results: 2, isFolder: false, fileExtensions: ["mov"]))
        XCTAssertNotNil(OutFile.problem("a.mov", results: 2, isFolder: false, fileExtensions: ["mov"]))
    }

    func testNamesAFileFollowsTheExtensionAndTheFolder() {
        XCTAssertTrue(OutFile.namesAFile("x/words.json", isFolder: false))
        XCTAssertFalse(OutFile.namesAFile("words.json", isFolder: true))
        XCTAssertFalse(OutFile.namesAFile("words", isFolder: false))
    }

    // MARK: - The execute() call

    func testCheckThrowsAUsageErrorSoTheExitIsTwo() {
        XCTAssertThrowsError(try OutFile.check("never-a-folder-\(UUID().uuidString).mp4", results: 2)) { error in
            guard let error = error as? CLIError else { return XCTFail("not a CLIError: \(error)") }
            XCTAssertEqual(error.code, .usage)
            XCTAssertEqual(error.code.exitCode.rawValue, 2)
            XCTAssertTrue(error.message.contains("this run writes 2"))
        }
    }

    func testCheckPassesNothingOneResultAndRealFolders() throws {
        XCTAssertNoThrow(try OutFile.check(nil, results: 5))
        XCTAssertNoThrow(try OutFile.check("one.mp4", results: 1))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("outfile-\(UUID().uuidString).mp4")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNoThrow(try OutFile.check(folder.path, results: 5))
    }

    func testCheckPassesItsSettingsThrough() {
        XCTAssertNoThrow(try OutFile.check("x.mp4", results: 2, fileExtensions: ["mov"]))
        XCTAssertThrowsError(try OutFile.check("x.png", results: 2, option: "--output", folderOption: "--out")) { error in
            XCTAssertTrue((error as? CLIError)?.message.hasPrefix("--output x.png") == true)
            XCTAssertTrue((error as? CLIError)?.message.contains("give --out a folder") == true)
        }
    }
}
