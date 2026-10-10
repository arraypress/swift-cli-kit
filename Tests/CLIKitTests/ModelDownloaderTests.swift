//
//  ModelDownloaderTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The parts of a model download that decide what is trusted: which files
//  belong to the model, whether an arrived file is the published one, and
//  when a download is not attempted at all. One live fetch of a 2 MB model
//  runs only with CLIKIT_LIVE=1 set.
//

import XCTest
@testable import CLIKit

final class ModelDownloaderTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("model-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func entry(_ path: String, _ type: String = "file") -> ModelDownloader.Entry {
        .init(type: type, path: path, oid: nil, size: 1, lfs: nil)
    }

    func testOnlyTheNamedFoldersAreFetched() {
        let listing = [entry(".gitattributes"), entry("README.md"), entry("a.aimodel", "directory"),
                       entry("a.aimodel/weights.bin"), entry("a.aimodel/meta.json"),
                       entry("a.aimodel-old/weights.bin"), entry("support/vocab.json")]
        let picked = ModelDownloader.files(in: listing, under: ["a.aimodel", "support"]).map(\.path)
        XCTAssertEqual(picked, ["a.aimodel/weights.bin", "a.aimodel/meta.json", "support/vocab.json"])
    }

    func testAFileIsCheckedAgainstItsPublishedHash() throws {
        let file = root.appendingPathComponent("hello.txt")
        try Data("hello\n".utf8).write(to: file)
        let small = ModelDownloader.Entry(type: "file", path: "hello.txt",
                                          oid: "ce013625030ba8dba906f756967f9e9ca394464a", size: 6, lfs: nil)
        XCTAssertTrue(try ModelDownloader.verify(file, against: small))
        let large = ModelDownloader.Entry(type: "file", path: "hello.txt", oid: "unused", size: 134,
                                          lfs: .init(oid: "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03", size: 6))
        XCTAssertTrue(try ModelDownloader.verify(file, against: large))
        let wrong = ModelDownloader.Entry(type: "file", path: "hello.txt", oid: nil, size: 6,
                                          lfs: .init(oid: String(repeating: "0", count: 64), size: 6))
        XCTAssertFalse(try ModelDownloader.verify(file, against: wrong))
        let short = ModelDownloader.Entry(type: "file", path: "hello.txt", oid: nil, size: 7, lfs: nil)
        XCTAssertFalse(try ModelDownloader.verify(file, against: short))
    }

    func testDownloadsCanBeTurnedOff() {
        XCTAssertTrue(ModelDownloader.isAllowed(environment: [:]))
        XCTAssertTrue(ModelDownloader.isAllowed(environment: ["NO_MODEL_DOWNLOAD": "0"]))
        XCTAssertFalse(ModelDownloader.isAllowed(environment: ["NO_MODEL_DOWNLOAD": "1"]))
        XCTAssertFalse(ModelDownloader.isAllowed(environment: ["NO_MODEL_DOWNLOAD": "yes"]))
    }

    func testNothingIsFetchedWhenTurnedOffOrWhenTheRunNamedAPath() async throws {
        let source = ModelSource(repository: "arraypress/tune-crepe", paths: ["tune-crepe-tiny-float32.aimodel"])
        let location = ModelLocation(service: "tune", names: ["tune-crepe-tiny-float32.aimodel"],
                                     download: "tune model install …", source: source)
        for (explicit, environment) in [(nil, ["NO_MODEL_DOWNLOAD": "1"]), ("~/nowhere.aimodel", [:])] as [(String?, [String: String])] {
            do {
                _ = try await location.obtain(explicit: explicit, quiet: true, environment: environment, supportFolder: root)
                XCTFail("should have refused")
            } catch let error as CLIError {
                XCTAssertEqual(error.code, .notFound)
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testALiveFetchInstallsAndChecksTheModel() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLIKIT_LIVE"] == "1", "set CLIKIT_LIVE=1 to fetch from huggingface.co")
        let source = ModelSource(repository: "arraypress/tune-crepe", paths: ["tune-crepe-tiny-float32.aimodel"], licence: "MIT")
        let location = ModelLocation(service: "tune", names: ["tune-crepe-tiny-float32.aimodel"],
                                     download: "tune model install …", source: source)
        let model = try await location.obtain(explicit: nil, quiet: true, environment: [:], supportFolder: root)
        XCTAssertEqual(model.lastPathComponent, "tune-crepe-tiny-float32.aimodel")
        XCTAssertGreaterThan(ModelLocation.size(of: model), 1_000_000)
        // Nothing half-made is left beside it.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["tune-crepe-tiny-float32.aimodel"])
    }
}
