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

import os
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

    func testCancellingStopsALiveTransfer() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLIKIT_LIVE"] == "1", "set CLIKIT_LIVE=1 to fetch from huggingface.co")
        // 224 MB: far more than arrives in the second before the cancel.
        let source = ModelSource(repository: "arraypress/stems-mdx", paths: [], licence: "MIT")
        let url = ModelDownloader.fileURL(source, "stems-mdx23c-instvoc-float16.aimodel/main.mlirb")
        let destination = root.appendingPathComponent("main.mlirb")
        let fetch = Task {
            try await ModelDownloader.fetch(url, to: destination, service: "test", received: { _ in })
        }
        try await Task.sleep(for: .seconds(1))
        let cancelled = ContinuousClock.now
        fetch.cancel()
        do {
            try await fetch.value
            XCTFail("the transfer finished despite the cancel")
        } catch is CancellationError {
            XCTAssertLessThan(ContinuousClock.now - cancelled, .seconds(2), "the cancel did not stop the transfer")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testTheStagingFolderIsNamedForTheModelNotTheRun() {
        let a = ModelSource(repository: "arraypress/tune-crepe", paths: ["b.aimodel", "a.aimodel"], licence: "MIT")
        let b = ModelSource(repository: "arraypress/tune-crepe", paths: ["a.aimodel", "b.aimodel"], licence: "MIT")
        let other = ModelSource(repository: "arraypress/tune-crepe", paths: ["a.aimodel"], licence: "MIT")
        XCTAssertEqual(ModelDownloader.stagingName(for: a), ModelDownloader.stagingName(for: b), "the same model, the same folder")
        XCTAssertNotEqual(ModelDownloader.stagingName(for: a), ModelDownloader.stagingName(for: other))
        XCTAssertTrue(ModelDownloader.stagingName(for: a).hasPrefix(".download-"))
        XCTAssertFalse(ModelDownloader.isAbandonedStaging(ModelDownloader.stagingName(for: a)), "resumable, so never swept")
        XCTAssertTrue(ModelDownloader.isAbandonedStaging(".download-\(UUID().uuidString)"), "a pre-0.13.2 run folder")
        XCTAssertFalse(ModelDownloader.isAbandonedStaging("model.aimodel"))
    }

    func testOldRunFoldersAreSweptAndResumableOnesKept() throws {
        let old = root.appendingPathComponent(".download-\(UUID().uuidString)")
        let source = ModelSource(repository: "arraypress/tune-crepe", paths: ["a.aimodel"], licence: "MIT")
        let keep = root.appendingPathComponent(ModelDownloader.stagingName(for: source))
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        ModelDownloader.removeAbandonedStaging(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }

    func testTheServersAnswerDecidesHowToContinue() {
        XCTAssertEqual(ModelDownloader.continuation(have: 500, status: 206), .append)
        XCTAssertEqual(ModelDownloader.continuation(have: 500, status: 200), .restart, "Range ignored: start over")
        XCTAssertEqual(ModelDownloader.continuation(have: 0, status: 200), .restart)
        XCTAssertEqual(ModelDownloader.continuation(have: 500, status: 416), .complete)
        XCTAssertEqual(ModelDownloader.continuation(have: 0, status: 206), .fail(206), "a partial answer to a full request")
        XCTAssertEqual(ModelDownloader.continuation(have: 500, status: 404), .fail(404))
    }

    func testALiveTransferCutOffHalfwayContinuesWhereItStopped() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLIKIT_LIVE"] == "1", "set CLIKIT_LIVE=1 to fetch from huggingface.co")
        let source = ModelSource(repository: "arraypress/stems-mdx", paths: [], licence: "MIT")
        let url = ModelDownloader.fileURL(source, "stems-mdx23c-instvoc-float16.aimodel/main.mlirb")
        let destination = root.appendingPathComponent("main.mlirb")
        let first = Task { try await ModelDownloader.fetch(url, to: destination, service: "test", received: { _ in }) }
        try await Task.sleep(for: .seconds(2))
        first.cancel()
        _ = try? await first.value
        let kept = ModelDownloader.fileSize(destination)
        XCTAssertGreaterThan(kept, 0, "what arrived before the cancel is kept")
        let starts = OSAllocatedUnfairLock<[Int64]>(initialState: [])
        try await ModelDownloader.fetch(url, to: destination, service: "test", received: { n in starts.withLock { $0.append(n) } })
        XCTAssertEqual(starts.withLock { $0.first }, kept, "the second run starts from the bytes already there")
        let entry = ModelDownloader.Entry(type: "file", path: "stems-mdx23c-instvoc-float16.aimodel/main.mlirb", oid: nil,
                                          size: nil, lfs: try await Self.lfs(of: source, path: "stems-mdx23c-instvoc-float16.aimodel/main.mlirb"))
        XCTAssertTrue(try ModelDownloader.verify(destination, against: entry), "the stitched file matches the published SHA-256")
    }

    private static func lfs(of source: ModelSource, path: String) async throws -> ModelDownloader.Entry.LFS? {
        try await ModelDownloader.listing(of: source, service: "test").first { $0.path == path }?.lfs
    }
}
