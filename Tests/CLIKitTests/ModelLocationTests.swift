//
//  ModelLocationTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The lookup order — run, then shell, then installed — and the refusal to
//  install a file that is not the model, both with real files in a scratch
//  folder rather than Application Support.
//

import XCTest
@testable import CLIKit

final class ModelLocationTests: XCTestCase {

    private var root: URL!
    private let location = ModelLocation(service: "redub", folder: "stems",
                                         names: ["mdx_net.mlpackage", "mdx_net.mlmodelc"],
                                         environmentKey: "STEMS_MODEL", download: "stems install …")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("model-location-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func make(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testTheRunBeatsTheShellBeatsTheInstall() throws {
        let named = try make("named.mlpackage")
        let shell = try make("shell.mlpackage")
        let support = root.appendingPathComponent("support")
        let installed = try make("support/mdx_net.mlpackage")
        let environment = ["STEMS_MODEL": shell.path]
        XCTAssertEqual(try location.resolve(explicit: named.path, environment: environment, supportFolder: support).path, named.path)
        XCTAssertEqual(try location.resolve(explicit: nil, environment: environment, supportFolder: support).path, shell.path)
        XCTAssertEqual(try location.resolve(explicit: nil, environment: [:], supportFolder: support).path, installed.path)
    }

    func testTheSecondNameIsTriedWhenTheFirstIsAbsent() throws {
        let compiled = try make("support/mdx_net.mlmodelc")
        XCTAssertEqual(try location.resolve(explicit: nil, environment: [:],
                                            supportFolder: root.appendingPathComponent("support")).path, compiled.path)
    }

    func testAMissingModelIsNotFoundWithTheDownloadAsTheHint() {
        XCTAssertThrowsError(try location.resolve(explicit: nil, environment: [:],
                                                  supportFolder: root.appendingPathComponent("empty"))) { error in
            let failure = error as? CLIError
            XCTAssertEqual(failure?.code, .notFound)
            XCTAssertEqual(failure?.service, "redub")
            XCTAssertEqual(failure?.hint, "stems install …")
        }
    }

    func testTheFolderDefaultsToTheService() {
        XCTAssertEqual(ModelLocation(service: "img", names: ["x"], download: "").folder, "img")
    }

    func testOnlyTheModelInstalls() throws {
        let wrong = try make("other.mlpackage")
        XCTAssertThrowsError(try location.install(wrong.path, into: root.appendingPathComponent("support")))
        let right = try make("mdx_net.mlpackage")
        let installed = try location.install(right.path, into: root.appendingPathComponent("support"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
    }
}
