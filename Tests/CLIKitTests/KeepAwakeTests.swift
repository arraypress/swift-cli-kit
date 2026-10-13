//
//  KeepAwakeTests.swift
//  CLIKitTests
//
//  Created by David Sherlock on 2026.
//

import Foundation
import os
import XCTest
@testable import CLIKit

/// Counts holds and releases instead of touching the real power manager.
private final class FakeAssertions: PowerAssertions {

    struct State {
        var next: UInt32 = 1
        var held: [UInt32: String] = [:]
        var releases = 0
    }

    let state = OSAllocatedUnfairLock(initialState: State())
    let refuses: Bool

    init(refuses: Bool = false) { self.refuses = refuses }

    func create(name: String) -> UInt32? {
        guard !refuses else { return nil }
        return state.withLock { state in
            defer { state.next += 1 }
            state.held[state.next] = name
            return state.next
        }
    }

    func release(_ id: UInt32) {
        state.withLock { state in
            state.held[id] = nil
            state.releases += 1
        }
    }

    var held: [String] { state.withLock { Array($0.held.values) } }
    var releases: Int { state.withLock { $0.releases } }
}

final class KeepAwakeTests: XCTestCase {

    func testHoldNamesTheAssertionAndReleaseGivesItBack() {
        let fake = FakeAssertions()
        let token = KeepAwake.hold("imagine make: working", environment: [:], assertions: fake)
        XCTAssertNotNil(token)
        XCTAssertEqual(fake.held, ["imagine make: working"])
        token?.release()
        XCTAssertEqual(fake.held, [])
        token?.release()
        XCTAssertEqual(fake.releases, 1, "a second release must not release someone else's id")
    }

    func testDeallocationReleases() {
        let fake = FakeAssertions()
        do {
            let token = KeepAwake.hold("x: working", environment: [:], assertions: fake)
            XCTAssertNotNil(token)
            XCTAssertEqual(fake.held.count, 1)
        }
        XCTAssertEqual(fake.held, [])
        XCTAssertEqual(fake.releases, 1)
    }

    func testOptOutHoldsNothing() {
        for value in ["1", "true", "YES"] {
            let fake = FakeAssertions()
            XCTAssertNil(KeepAwake.hold("x", environment: [KeepAwake.disableKey: value], assertions: fake))
            XCTAssertEqual(fake.held, [])
        }
        for value in ["", "0", "no"] {
            XCTAssertTrue(KeepAwake.isAllowed(environment: [KeepAwake.disableKey: value]), value)
        }
    }

    func testRefusalIsNotAnError() {
        XCTAssertNil(KeepAwake.hold("x", environment: [:], assertions: FakeAssertions(refuses: true)))
    }

    func testReasonNamesToolAndCommand() {
        XCTAssertEqual(KeepAwake.reason(tool: "imagine", command: "make"), "imagine make: working")
        XCTAssertEqual(KeepAwake.reason(tool: "imagine", command: "imagine"), "imagine: working")
        XCTAssertEqual(KeepAwake.reason(tool: "img", command: nil), "img: working")
    }

    func testDuringReleasesOnThrow() async {
        struct Boom: Error {}
        do {
            _ = try await KeepAwake.during("x") { () async throws(Boom) -> Int in throw Boom() }
            XCTFail("should throw")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    func testEnvironmentFlag() {
        XCTAssertTrue(["K": "Yes"].flagIsSet("K"))
        XCTAssertFalse(["K": "0"].flagIsSet("K"))
        XCTAssertFalse([String: String]().flagIsSet("K"))
    }
}
