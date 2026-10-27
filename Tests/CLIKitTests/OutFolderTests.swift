//
//  OutFolderTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The bug under test: `--out clip.mp4` made a FOLDER called clip.mp4 and
//  exited 0. Each rule has a test that fails when the rule is broken.
//

import ArgumentParser
import XCTest
@testable import CLIKit

final class OutFolderTests: XCTestCase {

    // MARK: - What is refused

    func testAFileNameIsRefusedAndTheMessagePointsAtTheFileOption() {
        XCTAssertEqual(
            OutFolder.problem("renders/clip.mp4", isFolder: false),
            "--out is a folder for the results, and clip.mp4 is a file name: to name the file, use -o renders/clip.mp4; with several inputs, give --out a folder name."
        )
    }

    func testTheExtensionIsMatchedWhateverItsCase() {
        XCTAssertNotNil(OutFolder.problem("Cover.PNG", isFolder: false))
    }

    func testWithoutAFileOptionTheMessageAsksOnlyForAFolder() {
        XCTAssertEqual(
            OutFolder.problem("out.wav", isFolder: false, option: "-o", fileOption: nil),
            "-o is a folder for the results, and out.wav is a file name: give -o a folder name."
        )
    }

    func testTheOptionsAreNamedAsTheToolSpellsThem() {
        let message = OutFolder.problem("a.png", isFolder: false, option: "--into", fileOption: "--file")
        XCTAssertEqual(message, "--into is a folder for the results, and a.png is a file name: to name the file, use --file a.png; with several inputs, give --into a folder name.")
    }

    // MARK: - What is accepted

    func testAPlainFolderNameIsAccepted() {
        XCTAssertNil(OutFolder.problem("renders", isFolder: false))
        XCTAssertNil(OutFolder.problem("~/Desktop/out", isFolder: false))
    }

    func testAnExtensionThatIsNotAFileNameIsAccepted() {
        // Folders called v1.2 or 2026.10 are common; only known file names are refused.
        XCTAssertNil(OutFolder.problem("build/v1.2", isFolder: false))
        XCTAssertNil(OutFolder.problem("shots.final", isFolder: false))
    }

    func testAnExistingFolderIsAcceptedWhateverItIsCalled() {
        XCTAssertNil(OutFolder.problem("clip.mp4", isFolder: true))
        XCTAssertNil(OutFolder.problem("clip.mp4", isFolder: true, alsoNames: "srt"))
    }

    func testTheCallersOwnExtensionsReplaceTheDefaults() {
        XCTAssertNil(OutFolder.problem("clip.mp4", isFolder: false, fileExtensions: ["mov"]))
        XCTAssertNotNil(OutFolder.problem("clip.mov", isFolder: false, fileExtensions: ["mov"]))
    }

    func testTheDefaultsCoverVideoAudioImagesDocumentsAndSubtitles() {
        for ext in ["mp4", "mov", "m4a", "wav", "flac", "png", "jpg", "heic", "pdf", "srt", "vtt", "json"] {
            XCTAssertTrue(OutFolder.fileExtensions.contains(ext), ext)
        }
        XCTAssertTrue(OutFolder.fileExtensions.allSatisfy { $0 == $0.lowercased() && !$0.hasPrefix(".") })
    }

    // MARK: - An option that is a folder or one file

    func testTheOneFileTheOptionAlsoNamesIsAccepted() {
        XCTAssertNil(OutFolder.problem("words.srt", isFolder: false, option: "-o", alsoNames: "srt"))
        XCTAssertNil(OutFolder.problem("WORDS.SRT", isFolder: false, option: "-o", alsoNames: "srt"))
        XCTAssertNil(OutFolder.problem("words.srt", isFolder: false, option: "-o", alsoNames: "SRT"))
    }

    func testAnyOtherFileNameIsRefusedWithTheNameItShouldHave() {
        XCTAssertEqual(
            OutFolder.problem("out/words.json", isFolder: false, option: "-o", alsoNames: "srt"),
            "-o is a folder for the results or, for one input, the .srt file itself, and words.json is neither: name it words.srt, or give -o a folder name."
        )
    }

    // MARK: - The validate() call

    func testCheckThrowsAValidationErrorSoTheExitIsUsage() throws {
        XCTAssertThrowsError(try OutFolder.check("never-a-folder-\(UUID().uuidString).mp4")) { error in
            XCTAssertTrue(error is ValidationError)
            XCTAssertTrue("\(error)".contains("-o never-a-folder-"))
        }
    }

    func testCheckPassesNothingAndRealFolders() throws {
        XCTAssertNoThrow(try OutFolder.check(nil))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("outfolder-\(UUID().uuidString).mp4")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(OutFolder.isFolder(folder.path))
        XCTAssertNoThrow(try OutFolder.check(folder.path))
    }

    func testATildeIsExpandedBeforeLooking() {
        XCTAssertTrue(OutFolder.isFolder("~"))
    }

    func testAFileIsNotAFolder() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("outfolder-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(OutFolder.isFolder(file.path))
        XCTAssertThrowsError(try OutFolder.check(file.path))
    }

    func testCheckPassesItsSettingsThrough() {
        XCTAssertNoThrow(try OutFolder.check("x.mp4", fileExtensions: ["mov"]))
        XCTAssertNoThrow(try OutFolder.check("x.srt", option: "-o", alsoNames: "srt"))
        XCTAssertThrowsError(try OutFolder.check("x.wav", option: "-o", fileOption: nil)) { error in
            XCTAssertEqual("\(error)", "-o is a folder for the results, and x.wav is a file name: give -o a folder name.")
        }
    }
}
