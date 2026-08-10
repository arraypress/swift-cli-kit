//
//  ManifestTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The fixture mirrors real `--experimental-dump-help` output, including the
//  key drift for permitted values that cost a debugging round.
//

import XCTest
@testable import CLIKit

final class ManifestTests: XCTestCase {

    // MARK: - Fixture

    private let dump = Data("""
    {
      "command": {
        "commandName": "yt-fetch",
        "abstract": "Fetch YouTube metadata.",
        "arguments": [
          {"kind":"flag","names":[{"kind":"long","name":"version"}],"isOptional":true,"abstract":"Show the version."},
          {"kind":"flag","names":[{"kind":"long","name":"help"}],"isOptional":true,"abstract":"Show help."}
        ],
        "subcommands": [
          {
            "commandName": "search",
            "abstract": "Search YouTube.",
            "discussion": "Quote multi-word queries.",
            "arguments": [
              {"kind":"positional","valueName":"query","isOptional":false,"abstract":"Search terms."},
              {"kind":"option","valueName":"limit","isOptional":true,"defaultValue":"20",
               "names":[{"kind":"long","name":"limit"},{"kind":"short","name":"n"}],"abstract":"Max results."},
              {"kind":"option","valueName":"sort","isOptional":true,"defaultValue":"relevance",
               "names":[{"kind":"long","name":"sort"}],"allValues":["relevance","date"],"abstract":"Ordering."},
              {"kind":"option","valueName":"fields","isOptional":true,"isRepeating":true,
               "names":[{"kind":"long","name":"fields"}],"abstract":"Limit fields."},
              {"kind":"flag","names":[{"kind":"long","name":"full"}],"isOptional":true,"abstract":"Everything."},
              {"kind":"flag","names":[{"kind":"long","name":"json"}],"isOptional":true,"abstract":"Force JSON."}
            ]
          },
          {
            "commandName": "channel",
            "abstract": "Channel operations.",
            "defaultSubcommand": "info",
            "arguments": [],
            "subcommands": [
              {"commandName":"info","abstract":"Profile.",
               "arguments":[{"kind":"positional","valueName":"channel","isOptional":false,"abstract":"A channel."}]},
              {"commandName":"videos","abstract":"Uploads.",
               "arguments":[{"kind":"positional","valueName":"channel","isOptional":false,"abstract":"A channel."}]}
            ]
          },
          {
            "commandName": "group",
            "abstract": "Pure dispatcher.",
            "arguments": [],
            "subcommands": [{"commandName":"leaf","abstract":"A leaf.","arguments":[]}]
          },
          {"commandName": "help", "abstract": "Show help.", "arguments": []},
          {"commandName": "hidden", "abstract": "Hidden.", "shouldDisplay": false, "arguments": []}
        ]
      }
    }
    """.utf8)

    private func build() throws -> Manifest {
        try Manifest.build(dumpHelpJSON: dump, service: "youtube", requiresAuth: false, version: "0.2.0")
    }

    // MARK: - Structure

    func testHeaderFieldsComeFromTheCaller() throws {
        let m = try build()
        XCTAssertEqual(m.tool, "yt-fetch")
        XCTAssertEqual(m.version, "0.2.0")
        XCTAssertEqual(m.service, "youtube")
        XCTAssertFalse(m.requiresAuth)
    }

    func testEveryOutputFormatAndExitCodeIsAdvertised() throws {
        let m = try build()
        XCTAssertEqual(Set(m.formats), Set(OutputFormat.allCases.map(\.rawValue)))
        for code in CLIExitCode.allCases {
            XCTAssertNotNil(m.exitCodes[String(code.rawValue)], "exit \(code.rawValue) undocumented")
        }
    }

    func testCommandsAreFlattenedWithPaths() throws {
        let invocations = try build().commands.map(\.invocation)
        XCTAssertTrue(invocations.contains("yt-fetch search"))
        XCTAssertTrue(invocations.contains("yt-fetch channel videos"))
        XCTAssertTrue(invocations.contains("yt-fetch group leaf"))
    }

    func testGroupWithADefaultSubcommandIsInvocable() throws {
        // `yt-fetch channel @name` works because `info` is the default.
        XCTAssertTrue(try build().commands.contains { $0.path == ["channel"] })
    }

    func testPureDispatcherIsNotInvocable() throws {
        // `yt-fetch group` alone does nothing; only `group leaf` runs.
        XCTAssertFalse(try build().commands.contains { $0.path == ["group"] })
    }

    func testParserSuppliedAndHiddenCommandsAreExcluded() throws {
        let paths = try build().commands.map(\.path)
        XCTAssertFalse(paths.contains(["help"]))
        XCTAssertFalse(paths.contains(["hidden"]))
    }

    // MARK: - Arguments

    private func command(_ invocation: String) throws -> Manifest.Command {
        try XCTUnwrap(build().commands.first { $0.invocation == invocation })
    }

    func testPositionalIsRequiredAndUnprefixed() throws {
        let query = try XCTUnwrap(command("yt-fetch search").arguments.first)
        XCTAssertEqual(query.name, "query")
        XCTAssertEqual(query.kind, "positional")
        XCTAssertTrue(query.required)
    }

    func testOptionCarriesLongShortAndDefault() throws {
        let limit = try XCTUnwrap(command("yt-fetch search").arguments.first { $0.name == "--limit" })
        XCTAssertEqual(limit.short, "-n")
        XCTAssertEqual(limit.defaultValue, "20")
        XCTAssertFalse(limit.required)
    }

    func testPermittedValuesAreReadFromAllValues() throws {
        // Regression: the key is `allValues` in this ArgumentParser build, not
        // `allValueStrings`. Reading only the latter silently dropped every enum.
        let sort = try XCTUnwrap(command("yt-fetch search").arguments.first { $0.name == "--sort" })
        XCTAssertEqual(sort.values, ["relevance", "date"])
    }

    func testPermittedValuesFallBackToAllValueStrings() throws {
        let json = Data("""
        {"command":{"commandName":"t","arguments":[
          {"kind":"option","valueName":"mode","isOptional":true,
           "names":[{"kind":"long","name":"mode"}],"allValueStrings":["a","b"]}]}}
        """.utf8)
        let m = try Manifest.build(dumpHelpJSON: json, service: "s", requiresAuth: false, version: "1")
        XCTAssertEqual(m.commands[0].arguments.first?.values, ["a", "b"])
    }

    func testPermittedValuesFallBackToCompletionKind() throws {
        let json = Data("""
        {"command":{"commandName":"t","arguments":[
          {"kind":"option","valueName":"mode","isOptional":true,
           "names":[{"kind":"long","name":"mode"}],"completionKind":{"list":{"values":["x","y"]}}}]}}
        """.utf8)
        let m = try Manifest.build(dumpHelpJSON: json, service: "s", requiresAuth: false, version: "1")
        XCTAssertEqual(m.commands[0].arguments.first?.values, ["x", "y"])
    }

    func testPermittedValuesScrapedFromHelpTextAsALastResort() {
        XCTAssertEqual(
            Manifest.Argument.parseValues(from: "Ordering. (values: top, newest; default: top)"),
            ["top", "newest"]
        )
        XCTAssertNil(Manifest.Argument.parseValues(from: "Just a description."))
    }

    func testRepeatingArgumentIsMarked() throws {
        let fields = try XCTUnwrap(command("yt-fetch search").arguments.first { $0.name == "--fields" })
        XCTAssertTrue(fields.repeating)
    }

    func testHelpAndVersionAreNeverExposed() throws {
        for command in try build().commands {
            XCTAssertFalse(command.arguments.contains { $0.name == "--help" }, command.invocation)
            XCTAssertFalse(command.arguments.contains { $0.name == "--version" }, command.invocation)
        }
    }

    // MARK: - Robustness

    func testUnknownKeysAreToleratedNotFatal() throws {
        // The dump comes from a dependency we do not control; a new key must
        // never break `describe`.
        let json = Data("""
        {"command":{"commandName":"t","brandNewKey":42,
         "arguments":[{"kind":"flag","names":[{"kind":"long","name":"x"}],"futureField":true}]}}
        """.utf8)
        XCTAssertNoThrow(
            try Manifest.build(dumpHelpJSON: json, service: "s", requiresAuth: false, version: "1")
        )
    }

    func testMalformedDumpThrowsAParseFailure() {
        XCTAssertThrowsError(
            try Manifest.build(dumpHelpJSON: Data("not json".utf8), service: "s", requiresAuth: false, version: "1")
        ) { error in
            XCTAssertEqual((error as? CLIError)?.code, .parseFailure)
        }
    }

    func testManifestRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(try build())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["tool"] as? String, "yt-fetch")
        XCTAssertNotNil(object["commands"])
    }

    func testTextRenderingListsCommands() throws {
        let rendered = try build().renderText()
        XCTAssertTrue(rendered.contains("yt-fetch 0.2.0"))
        XCTAssertTrue(rendered.contains("yt-fetch channel videos"))
    }
}
