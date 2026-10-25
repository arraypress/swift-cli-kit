//
//  LocalOnlyCommandTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import ArgumentParser
import XCTest
@testable import CLIKit

final class LocalOnlyCommandTests: XCTestCase {

    struct Tool: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tool", subcommands: [Read.self, Access.self, Pin.self]
        )
    }
    struct Read: ParsableCommand {}
    struct Pin: ParsableCommand, LocalOnlyCommand {}
    struct Access: ParsableCommand, LocalOnlyCommand {
        static let configuration = CommandConfiguration(
            commandName: "access", subcommands: [Status.self, Allow.self], defaultSubcommand: Status.self
        )
    }
    struct Status: ParsableCommand {}
    struct Allow: ParsableCommand {}

    func testAMarkedLeafIsLocal() {
        XCTAssertTrue(CommandEffects.localOnly(in: Tool.self).contains(["pin"]))
    }

    func testEverythingUnderAMarkedGroupIsLocal() {
        // Marking the group is the point: a new subcommand added under it
        // later is covered without anyone remembering to mark it.
        let local = CommandEffects.localOnly(in: Tool.self)
        XCTAssertTrue(local.contains(["access"]), "the group runs its default, so it is a command too")
        XCTAssertTrue(local.contains(["access", "status"]))
        XCTAssertTrue(local.contains(["access", "allow"]))
    }

    func testTheRestStaysOffered() {
        XCTAssertFalse(CommandEffects.localOnly(in: Tool.self).contains(["read"]))
    }
}
