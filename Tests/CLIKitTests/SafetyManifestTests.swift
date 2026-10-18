//
//  SafetyManifestTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Declared effects in `describe` and as MCP annotations, and the retry
//  verdict in receipts and errors — each still reading old JSON.
//

import XCTest
@testable import CLIKit

final class SafetyManifestTests: XCTestCase {

    // MARK: Fixtures

    private func argument(_ name: String, kind: String = "flag") -> Manifest.Argument {
        .init(kind: kind, name: name, short: nil, required: false, repeating: false,
              summary: nil, defaultValue: nil, values: nil)
    }

    private func command(_ path: [String], _ effect: CommandEffect?) -> Manifest.Command {
        var command = Manifest.Command(
            path: path, invocation: (["tool"] + path).joined(separator: " "), summary: "Do \(path).",
            details: nil, arguments: [argument("--read-only"), argument("--wrap-untrusted"), argument("--full")]
        )
        command.effect = effect
        return command
    }

    private func manifest() -> Manifest {
        Manifest(tool: "tool", summary: nil, details: nil, version: "1.0.0", service: "tool",
                 requiresAuth: false, formats: ["json"], exitCodes: [:],
                 commands: [command(["list"], .readOnly),
                            command(["send"], .acting(destructive: false)),
                            command(["delete"], .acting(destructive: true, idempotent: true)),
                            command(["mystery"], .undeclared),
                            command(["legacy"], nil)])
    }

    private func tools(_ server: MCPServer) -> [String: [String: Any]] {
        Dictionary(uniqueKeysWithValues: server.toolDefinitions().map { ($0["name"] as! String, $0) })
    }

    // MARK: MCP annotations

    func testEachToolCarriesItsHints() throws {
        let tools = tools(MCPServer(manifest: manifest()) { _ in .init(stdout: "", stderr: "", exitCode: 0) })

        XCTAssertEqual(tools["tool_list"]?["annotations"] as? [String: Bool], ["readOnlyHint": true])
        XCTAssertEqual(tools["tool_send"]?["annotations"] as? [String: Bool],
                       ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false])
        XCTAssertEqual(tools["tool_delete"]?["annotations"] as? [String: Bool],
                       ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": true])
        XCTAssertEqual(tools["tool_mystery"]?["annotations"] as? [String: Bool],
                       ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false],
                       "undeclared is described as the worst case")
        XCTAssertEqual(tools["tool_legacy"]?["annotations"] as? [String: Bool],
                       ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false])
    }

    func testAReadOnlyServerOffersAndRunsOnlyReads() throws {
        let server = MCPServer(manifest: manifest(), readOnly: true) { argv in
            .init(stdout: "ran \(argv)", stderr: "", exitCode: 0)
        }
        XCTAssertEqual(Set(tools(server).keys), ["tool_list"])

        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tool_send","arguments":{}}}"#
        let reply = try XCTUnwrap(server.handle(Data(call.utf8)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        XCTAssertNotNil(object["error"], "an acting tool is unknown to a read-only server")
        XCTAssertNil(object["result"])
    }

    func testSafetyFlagsStayOutOfToolSchemas() throws {
        let send = command(["send"], .acting())
        let properties = try XCTUnwrap(MCPServer.inputSchema(for: send)["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["full"])
        let argv = try MCPServer.argumentVector(for: send, arguments: ["read-only": true, "wrap-untrusted": false,
                                                                     "no-wrap-untrusted": true, "full": true])
        XCTAssertEqual(argv, ["send", "--full"], "a call cannot switch the server's safety off")
    }

    // MARK: describe

    func testTheManifestRecordsEffectsAndSafety() throws {
        let dump = #"""
        {"command":{"commandName":"tool","subcommands":[
          {"commandName":"list","arguments":[]},
          {"commandName":"send","arguments":[]},
          {"commandName":"odd","arguments":[]}]}}
        """#
        let built = try Manifest.build(dumpHelpJSON: Data(dump.utf8), service: "tool", requiresAuth: false,
                                       version: "1.0.0", effects: [["list"]: .readOnly, ["send"]: .acting()])
        let effects = Dictionary(uniqueKeysWithValues: built.commands.map { ($0.path, $0.effect) })
        XCTAssertEqual(effects[["list"]], .readOnly)
        XCTAssertEqual(effects[["send"]], .acting())
        XCTAssertEqual(effects[["odd"]], .undeclared, "missing from the table means undeclared")
        XCTAssertEqual(built.safety?.readOnlyEnvironment, "CLIKIT_READ_ONLY")
        XCTAssertEqual(built.safety?.untrustedMarker, "<<untrusted:TOKEN>>…<</untrusted:TOKEN>>")

        let text = built.renderText()
        XCTAssertTrue(text.contains("[reads]"), text)
        XCTAssertTrue(text.contains("[acts, destructive]"), text)
        XCTAssertTrue(text.contains("[undeclared]"), text)

        let json = String(decoding: try JSONEncoder().encode(built), as: UTF8.self)
        XCTAssertTrue(json.contains(#""effect":{"destructive":false,"idempotent":true,"kind":"read_only"}"#)
                      || json.contains(#""kind":"read_only""#), json)
    }

    func testAManifestFromAnOlderCLIKitStillDecodes() throws {
        let old = #"""
        {"tool":"t","version":"0.1.0","service":"t","requiresAuth":false,"formats":["json"],"exitCodes":{},
         "commands":[{"path":["a"],"invocation":"t a","arguments":[]}]}
        """#
        let decoded = try JSONDecoder().decode(Manifest.self, from: Data(old.utf8))
        XCTAssertNil(decoded.commands[0].effect)
        XCTAssertNil(decoded.safety)
    }

    // MARK: Retry verdicts

    func testTheVerdictsAreAPublicContract() {
        XCTAssertEqual(RetryVerdict.allCases.map(\.rawValue),
                       ["not_started", "in_flight", "may_have_completed", "completed"])
        XCTAssertEqual(RetryVerdict.allCases.filter(\.isSafeToRetry), [.notStarted])
    }

    func testDoubtOutranksCertaintyWhenCombined() {
        XCTAssertEqual(RetryVerdict.combined([.completed, .mayHaveCompleted, .notStarted]), .mayHaveCompleted)
        XCTAssertEqual(RetryVerdict.combined([.completed, .inFlight]), .inFlight)
        XCTAssertEqual(RetryVerdict.combined([.notStarted, .completed]), .completed)
        XCTAssertNil(RetryVerdict.combined([]))
    }

    func testAChangeWithoutAVerdictEncodesExactlyAsBefore() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = Change(.created, subject: "chat 7", detail: ["mode": "send"])
        XCTAssertEqual(String(decoding: try encoder.encode(plain), as: UTF8.self),
                       #"{"detail":{"mode":"send"},"kind":"created","subject":"chat 7"}"#)

        let doubtful = plain.with(retry: .mayHaveCompleted)
        XCTAssertEqual(String(decoding: try encoder.encode(doubtful), as: UTF8.self),
                       #"{"detail":{"mode":"send"},"kind":"created","retry":"may_have_completed","subject":"chat 7"}"#)

        // A receipt written before 0.20 reads back, and a plan still diffs equal to itself.
        let old = #"{"tool":"t","action":"send","at":"2026-10-01T00:00:00Z","planned":true,"changes":[{"kind":"created","subject":"chat 7","detail":{}}]}"#
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(old.utf8))
        XCTAssertNil(receipt.changes[0].retry)
        XCTAssertNil(receipt.retry)
        XCTAssertEqual(receipt.changes[0], Change(.created, subject: "chat 7"))
    }

    func testAReceiptShowsItsVerdictInTextAndJSON() throws {
        let receipt = Receipt(tool: "t", action: "send", planned: false,
                              changes: [Change(.created, subject: "chat 7", to: "message 9", retry: .completed),
                                        Change(.created, subject: "chat 8", retry: .mayHaveCompleted)])
        XCTAssertEqual(receipt.retry, .mayHaveCompleted)
        let payload = ReceiptPayload(receipt)
        XCTAssertEqual(payload.renderText(), """
            created chat 7 → message 9 (retry: completed — retrying would do it again)
            created chat 8 (retry: may have completed — check before retrying)
            """)
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        XCTAssertTrue(json.contains(#""retry":"may_have_completed""#), json)

        let quiet = ReceiptPayload(Receipt(tool: "t", action: "x", planned: true, changes: [Change(.created, subject: "a")]))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(quiet), as: UTF8.self).contains("retry"))
    }

    func testAnErrorCarriesItsVerdictOnlyWhenItHasOne() {
        let plain = CLIError.upstream("boom", service: "t")
        XCTAssertFalse(plain.jsonEnvelope.contains("retry"))
        let doubtful = plain.with(retry: .mayHaveCompleted)
        XCTAssertEqual(doubtful.jsonEnvelope,
                       #"{"error":{"code":"upstream","message":"boom","service":"t","retry":"may_have_completed"}}"#)
        XCTAssertTrue(doubtful.humanDescription.contains("retry: may have completed"))
        XCTAssertEqual(doubtful.prefixed("x").retry, .mayHaveCompleted)
        XCTAssertEqual(CLIError.wrapping(OSAScriptError(reason: .timedOut(seconds: 1), retry: .mayHaveCompleted)).retry,
                       .mayHaveCompleted, "a described error keeps its verdict through classification")
    }
}
