//
//  CompiledModelCacheTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The walk over Core AI's compiled copies, on a scratch cache laid out the
//  way the OS lays it out: build / program / content hash.
//

import XCTest
@testable import CLIKit

final class CompiledModelCacheTests: XCTestCase {

    private var root: URL!
    private var cache: URL { root.appendingPathComponent("coreai-cache") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("compiled-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// An asset whose main.hash is `bytes`, and its hex.
    private func asset(_ name: String, in folder: URL, bytes: [UInt8]) throws -> (URL, String) {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(bytes).write(to: url.appendingPathComponent("main.hash"))
        try Data(repeating: 1, count: 100).write(to: url.appendingPathComponent("main.mlirb"))
        return (url, bytes.map { String(format: "%02x", $0) }.joined())
    }

    private func compiled(_ hash: String, program: String, build: String = "26A428", size: Int = 1000) throws -> URL {
        let entry = cache.appendingPathComponent(build).appendingPathComponent(program).appendingPathComponent(hash)
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        try Data(repeating: 2, count: size).write(to: entry.appendingPathComponent("blob"))
        return entry
    }

    func testTheHashIsMainHashAsHex() throws {
        let (url, hex) = try asset("m.aimodel", in: root, bytes: [0x6a, 0xad, 0x00, 0xff])
        XCTAssertEqual(CompiledModelCache.contentHash(of: url), "6aad00ff")
        XCTAssertEqual(hex, "6aad00ff")
        XCTAssertNil(CompiledModelCache.contentHash(of: root.appendingPathComponent("nothing.aimodel")))
    }

    func testCopiesAreFoundForEveryProgramAndBuildOrOne() throws {
        let (url, hash) = try asset("m.aimodel", in: root, bytes: [1, 2, 3])
        _ = try compiled(hash, program: "cutout")
        _ = try compiled(hash, program: "design")
        _ = try compiled(hash, program: "cutout", build: "26A500")
        _ = try compiled("ffff", program: "cutout")
        XCTAssertEqual(CompiledModelCache.copies(of: hash, root: cache).count, 3)
        XCTAssertEqual(CompiledModelCache.copies(of: hash, program: "design", root: cache).count, 1)
        XCTAssertTrue(CompiledModelCache.isCompiled(url, program: "cutout", root: cache))
        XCTAssertFalse(CompiledModelCache.isCompiled(url, program: "img", root: cache))
    }

    func testAssetsAreFoundInsideAModelFolder() throws {
        let folder = root.appendingPathComponent("bundle")
        _ = try asset("a.aimodel", in: folder, bytes: [1])
        _ = try asset("nested/b.aimodel", in: folder, bytes: [2])
        XCTAssertEqual(Set(CompiledModelCache.assets(under: folder).map(\.lastPathComponent)), ["a.aimodel", "b.aimodel"])
    }

    func testRemovingAModelTakesItsCopiesAndNoOthers() throws {
        let (url, hash) = try asset("m.aimodel", in: root, bytes: [9, 9])
        let mine = try compiled(hash, program: "cutout", size: 1000)
        let other = try compiled("0101", program: "cutout", size: 500)
        XCTAssertEqual(CompiledModelCache.bytes(of: url, root: cache), 1000)
        let freed = CompiledModelCache.removeModel(url, root: cache)
        XCTAssertEqual(freed, 1000 + 102)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertEqual(CompiledModelCache.removeModel(url, root: cache), 0)
    }
}
