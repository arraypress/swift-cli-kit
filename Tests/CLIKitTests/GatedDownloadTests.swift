//
//  GatedDownloadTests.swift
//  CLIKitTests
//
//  Created by David Sherlock on 2026.
//
//  Gated Hugging Face repositories: where the token comes from, what a
//  missing token or a refusal says (exit 3, with the way in), and — with
//  CLIKIT_LIVE=1 and a token that has access to facebook/sam3 — a real
//  authenticated download, including a large file through the CDN redirect,
//  cut off and continued.
//

import Foundation
import os
import XCTest
@testable import CLIKit

final class GatedDownloadTests: XCTestCase {

    /// A store holding at most one token.
    private struct OneTokenStore: CredentialStore {
        let token: String?
        func read(service: String, key: String) throws -> String? { service == "huggingface" && key == "token" ? token : nil }
        func write(service: String, key: String, value: String) throws {}
        func delete(service: String, key: String) throws {}
        func deleteAll(service: String) throws {}
        func storedServices() throws -> [String] { token == nil ? [] : ["huggingface"] }
        var locationDescription: String { "memory" }
    }

    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("hf-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".cache/huggingface"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testTheTokenIsFoundInOrderEnvironmentThenHFLoginThenTheStore() throws {
        let store = OneTokenStore(token: "from-store")
        XCTAssertNil(HuggingFaceToken.resolve(environment: [:], home: home, store: OneTokenStore(token: nil)))
        XCTAssertEqual(HuggingFaceToken.resolve(environment: [:], home: home, store: store)?.source, .store)

        try "from-hf-login\n".write(to: home.appendingPathComponent(".cache/huggingface/token"), atomically: true, encoding: .utf8)
        let cli = HuggingFaceToken.resolve(environment: [:], home: home, store: store)
        XCTAssertEqual(cli?.token, "from-hf-login", "trimmed, as hf writes it")
        XCTAssertEqual(cli?.source, .huggingFaceCLI)

        XCTAssertEqual(HuggingFaceToken.resolve(environment: ["HUGGING_FACE_HUB_TOKEN": "legacy"], home: home, store: store)?.token, "legacy")
        let env = HuggingFaceToken.resolve(environment: ["HF_TOKEN": "from-env", "HUGGING_FACE_HUB_TOKEN": "legacy"], home: home, store: store)
        XCTAssertEqual(env?.token, "from-env")
        XCTAssertEqual(env?.source, .environment)
        XCTAssertEqual(HuggingFaceToken.resolve(environment: ["HF_TOKEN": "  "], home: home, store: store)?.source,
                       .huggingFaceCLI, "a blank variable is no token")
    }

    func testHFHomeMovesTheLoginFile() throws {
        let moved = home.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        try "moved".write(to: moved.appendingPathComponent("token"), atomically: true, encoding: .utf8)
        XCTAssertEqual(HuggingFaceToken.resolve(environment: ["HF_HOME": moved.path], home: home,
                                                store: OneTokenStore(token: nil))?.token, "moved")
    }

    func testAGatedSourceWithNoTokenStopsWithTheWayIn() {
        let gated = ModelSource(repository: "black-forest-labs/FLUX.2-klein-9B", paths: ["x"], gated: true)
        XCTAssertNil(try ModelDownloader.token(for: ModelSource(repository: "a/b", paths: ["x"]), service: "t", environment: [:]),
                     "a public source sends no token")
        XCTAssertEqual(try ModelDownloader.token(for: gated, service: "t", environment: ["HF_TOKEN": "x"]), "x")
        // With no environment token this machine's own login may still be found,
        // so the refusal is checked through the error builder rather than the machine.
        let refusal = ModelDownloader.accessError(status: 403, repository: gated.repository, service: "imagine")
        XCTAssertEqual(refusal?.code, .authRequired)
        XCTAssertEqual(refusal?.code.exitCode, .authRequired, "exit 3")
        XCTAssertTrue(refusal?.hint?.contains("https://huggingface.co/black-forest-labs/FLUX.2-klein-9B") == true)
        XCTAssertTrue(refusal?.hint?.contains("hf auth login") == true)
        XCTAssertEqual(ModelDownloader.accessError(status: 401, repository: "a/b", service: "t")?.code, .authRequired)
        XCTAssertNil(ModelDownloader.accessError(status: 404, repository: "a/b", service: "t"))
        XCTAssertNil(ModelDownloader.accessError(status: 200, repository: "a/b", service: "t"))
    }

    // MARK: - Live

    private func liveToken() throws -> String {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLIKIT_LIVE"] == "1", "set CLIKIT_LIVE=1 to fetch from huggingface.co")
        guard let found = HuggingFaceToken.resolve() else { throw XCTSkip("no Hugging Face token on this machine") }
        return found.token
    }

    func testALiveGatedDownloadArrivesAndChecksOut() async throws {
        _ = try liveToken()
        let source = ModelSource(repository: "facebook/sam3", paths: ["config.json", "processor_config.json"],
                                 licence: "SAM License", gated: true)
        let installed = try await ModelDownloader.download(source, into: home, service: "test", progress: { _, _ in })
        XCTAssertEqual(installed.map(\.lastPathComponent), ["config.json", "processor_config.json"])
        XCTAssertGreaterThan(ModelDownloader.fileSize(installed[0]), 1000)
    }

    func testALiveRefusalIsExitThree() async throws {
        _ = try liveToken()
        let url = ModelDownloader.fileURL(ModelSource(repository: "facebook/sam3", paths: []), "config.json")
        do {
            try await ModelDownloader.fetch(url, to: home.appendingPathComponent("c.json"), service: "test",
                                            token: "hf_not_a_real_token", repository: "facebook/sam3", received: { _ in })
            XCTFail("a bad token should be refused")
        } catch let error as CLIError {
            XCTAssertEqual(error.code, .authRequired)
        }
    }

    func testALiveGatedLargeFileFollowsTheCDNRedirectAndContinues() async throws {
        let token = try liveToken()
        let url = ModelDownloader.fileURL(ModelSource(repository: "facebook/sam3", paths: []), "sam3.pt")
        let destination = home.appendingPathComponent("sam3.pt")
        func burst() async throws -> Int64? {
            let first = OSAllocatedUnfairLock<Int64?>(initialState: nil)
            let task = Task {
                try await ModelDownloader.fetch(url, to: destination, service: "test", token: token,
                                                repository: "facebook/sam3",
                                                received: { n in first.withLock { if $0 == nil { $0 = n } } })
            }
            try await Task.sleep(for: .seconds(3))
            task.cancel()
            _ = try? await task.value
            return first.withLock { $0 }
        }
        _ = try await burst()
        let kept = ModelDownloader.fileSize(destination)
        XCTAssertGreaterThan(kept, 0, "the authenticated request reached the CDN and bytes arrived")
        let resumedFrom = try await burst()
        XCTAssertEqual(resumedFrom, kept, "the second request continued from the bytes already there")
        XCTAssertGreaterThan(ModelDownloader.fileSize(destination), kept)
    }
}
