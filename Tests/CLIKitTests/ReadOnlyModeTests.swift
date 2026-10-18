//
//  ReadOnlyModeTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  --read-only and CLIKIT_READ_ONLY: every command not declared read-only is
//  refused, with exit 2, before its body runs.
//

import ArgumentParser
import os
import XCTest
@testable import CLIKit

/// What the fixture commands did — if anything.
private let touched = OSAllocatedUnfairLock(initialState: [String]())

private struct Tool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tool",
        subcommands: [ListCommand.self, SendCommand.self, Forgotten.self, Remove.self, Plain.self,
                      Group.self, Files.self, DescribeCommand<Tool>.self]
    )
}

extension Tool: ServiceProviding {
    static let service = ServiceSpec(id: "tool", displayName: "Tool", toolName: "tool", credentials: [])
}

private struct ListCommand: CLICommand {
    static let configuration = CommandConfiguration(commandName: "list")
    static let serviceID = "tool"
    static let commandEffect = CommandEffect.readOnly
    @OptionGroup var common: CommonOptions
    func execute() async throws { touched.withLock { $0.append("list") } }
}

private struct SendCommand: CLICommand {
    static let configuration = CommandConfiguration(commandName: "send")
    static let serviceID = "tool"
    static let commandEffect = CommandEffect.acting(destructive: false)
    @OptionGroup var common: CommonOptions
    func execute() async throws { touched.withLock { $0.append("send") } }
}

/// Acts, and forgot to say so.
private struct Forgotten: CLICommand {
    static let configuration = CommandConfiguration(commandName: "forgotten")
    static let serviceID = "tool"
    @OptionGroup var common: CommonOptions
    func execute() async throws { touched.withLock { $0.append("forgotten") } }
}

private struct Remove: MutatingCommand {
    static let configuration = CommandConfiguration(commandName: "remove")
    static let serviceID = "tool"
    static let actionName = "remove"
    @OptionGroup var common: CommonOptions
    @OptionGroup var write: WriteOptions
    func plan() async throws -> [Change] { [Change(.deleted, subject: "x")] }
    func apply(_ plan: [Change]) async throws -> [Change] { touched.withLock { $0.append("remove") }; return plan }
}

/// Lists, or with --save writes.
private struct Files: CLICommand, ConditionallyActing {
    static let configuration = CommandConfiguration(commandName: "files")
    static let serviceID = "tool"
    static let commandEffect = CommandEffect.acting(destructive: false)
    @Option var save: String?
    @OptionGroup var common: CommonOptions
    var actsThisRun: Bool { save != nil }
    func execute() async throws { touched.withLock { $0.append("files") } }
}

/// A plain ArgumentParser command — what CLIRunner's own gate covers.
private struct Plain: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "plain")
    func run() throws { touched.withLock { $0.append("plain") } }
}

/// A group whose default subcommand reads.
private struct Group: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "group", subcommands: [ListCommand.self, SendCommand.self], defaultSubcommand: ListCommand.self
    )
}

final class ReadOnlyModeTests: XCTestCase {

    override func setUp() {
        touched.withLock { $0.removeAll() }
    }

    private func parse(_ arguments: [String]) throws -> ParsableCommand {
        try Tool.parseAsRoot(arguments)
    }

    private func refusal(_ arguments: [String], environment: [String: String] = [:]) throws -> CLIError? {
        let command = try parse(arguments)
        do {
            try ReadOnlyMode.check(command, environment: environment)
            return nil
        } catch {
            return error
        }
    }

    // MARK: The gate

    func testTheFlagRefusesAnActingCommandWithExitTwo() throws {
        let error = try XCTUnwrap(try refusal(["send", "--read-only"]))
        XCTAssertEqual(error.code, .usage)
        XCTAssertEqual(error.code.exitCode.rawValue, 2)
        XCTAssertEqual(error.retry, .notStarted)
        XCTAssertTrue(error.message.contains("`send` changes things"), error.message)
        XCTAssertTrue(error.message.contains("nothing was done"), error.message)
    }

    func testTheEnvironmentRefusesWithoutTheFlag() throws {
        let error = try XCTUnwrap(try refusal(["send"], environment: ["CLIKIT_READ_ONLY": "1"]))
        XCTAssertTrue(error.message.contains("CLIKIT_READ_ONLY is set"), error.message)
        XCTAssertNil(try refusal(["send"], environment: ["CLIKIT_READ_ONLY": "0"]))
    }

    func testAReadOnlyCommandRunsUnderReadOnly() throws {
        XCTAssertNil(try refusal(["list", "--read-only"]))
        XCTAssertNil(try refusal(["list"], environment: ["CLIKIT_READ_ONLY": "1"]))
        XCTAssertNil(try refusal(["group", "--read-only"]), "a default subcommand that reads")
    }

    func testNothingIsRefusedWhenReadOnlyIsOff() throws {
        for command in [["send"], ["forgotten"], ["remove"], ["plain"]] {
            XCTAssertNil(try refusal(command), "\(command)")
        }
    }

    func testAnUndeclaredCommandFailsClosed() throws {
        let error = try XCTUnwrap(try refusal(["forgotten", "--read-only"]))
        XCTAssertTrue(error.message.contains("has not declared that it only reads"), error.message)
        XCTAssertNotNil(try refusal(["plain"], environment: ["CLIKIT_READ_ONLY": "true"]),
                        "a plain ParsableCommand declares nothing either")
    }

    func testAMutatingCommandMayPlanButNotApply() throws {
        XCTAssertNil(try refusal(["remove", "--dry-run", "--read-only"]), "a plan changes nothing")
        XCTAssertNotNil(try refusal(["remove", "--read-only"]))
    }

    func testAConditionallyActingCommandIsRefusedOnlyWhenItWouldAct() throws {
        XCTAssertNil(try refusal(["files", "--read-only"]), "listing only reads")
        XCTAssertNotNil(try refusal(["files", "--save", "/tmp/x", "--read-only"]))
        XCTAssertEqual(CommandEffects.table(for: Tool.self)[["files"]], .acting(destructive: false),
                       "describe and MCP still show the worst case")
    }

    // MARK: Before anything runs

    func testRunRefusesBeforeTheBodyRuns() async throws {
        for name in ["send", "forgotten", "remove"] {
            var command = try XCTUnwrap(try parse([name, "--read-only"]) as? AsyncParsableCommand)
            do {
                try await command.run()
                XCTFail("\(name) ran under --read-only")
            } catch let exit as ExitCode {
                XCTAssertEqual(exit.rawValue, 2, name)
            }
        }
        XCTAssertEqual(touched.withLock { $0 }, [], "nothing was touched")

        var list = try XCTUnwrap(try parse(["list", "--read-only"]) as? AsyncParsableCommand)
        try await list.run()
        XCTAssertEqual(touched.withLock { $0 }, ["list"])
    }

    // MARK: Declarations

    func testUndeclaredCommandsAreListedForATest() {
        XCTAssertEqual(CommandEffects.undeclared(in: Tool.self), ["tool forgotten", "tool plain"])
    }

    func testTheTableCoversEveryInvocableCommand() {
        let table = CommandEffects.table(for: Tool.self)
        XCTAssertEqual(table[["list"]], .readOnly)
        XCTAssertEqual(table[["send"]], .acting(destructive: false))
        XCTAssertEqual(table[["remove"]], .acting(), "a MutatingCommand acts by default")
        XCTAssertEqual(table[["forgotten"]], .undeclared)
        XCTAssertEqual(table[["group"]], .readOnly, "a group runs as its default subcommand")
        XCTAssertEqual(table[["group", "send"]], .acting(destructive: false))
        XCTAssertEqual(table[["describe"]], .readOnly)
        XCTAssertNil(table[[]], "the root only dispatches")
        XCTAssertEqual(CommandEffects.refusedUnderReadOnly(in: Tool.self),
                       ["tool files", "tool forgotten", "tool group send", "tool plain", "tool remove", "tool send"])
    }

    func testTheBuiltInCommandsDeclareThemselves() {
        XCTAssertEqual(CommandEffects.effect(of: AuthCommand<Tool>.Login.self).kind, .acting)
        XCTAssertEqual(CommandEffects.effect(of: AuthCommand<Tool>.Logout.self).kind, .acting)
        XCTAssertEqual(CommandEffects.effect(of: AuthCommand<Tool>.Status.self), .readOnly)
        XCTAssertEqual(CommandEffects.effect(of: CacheCommand<Tool>.Info.self), .readOnly)
        XCTAssertEqual(CommandEffects.effect(of: CacheCommand<Tool>.Clear.self).kind, .acting)
        XCTAssertEqual(CommandEffects.effect(of: MCPCommand<Tool>.self), .readOnly)
        XCTAssertEqual(CommandEffects.effect(of: DescribeCommand<Tool>.self), .readOnly)
    }

    func testTheReadOnlyFlagParses() throws {
        XCTAssertTrue(try CommonOptions.parse(["--read-only"]).readOnly)
        XCTAssertFalse(try CommonOptions.parse([]).readOnly)
    }
}
