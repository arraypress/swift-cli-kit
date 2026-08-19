//
//  MCPServerTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The server's message handling is a pure function with execution injected, so
//  every protocol behaviour is testable without spawning a process.
//

import XCTest
@testable import CLIKit

final class MCPServerTests: XCTestCase {

    // MARK: - Fixtures

    private func manifest() -> Manifest {
        Manifest(
            tool: "yt-fetch",
            summary: "Fetch YouTube metadata.",
            details: nil,
            version: "0.2.0",
            service: "youtube",
            requiresAuth: false,
            formats: ["json", "text"],
            exitCodes: ["0": "success", "1": "not found"],
            commands: [
                Manifest.Command(
                    path: [], invocation: "yt-fetch", summary: "Root.", details: nil, arguments: []
                ),
                Manifest.Command(
                    path: ["search"],
                    invocation: "yt-fetch search",
                    summary: "Search YouTube.",
                    details: "Quote multi-word queries.",
                    arguments: [
                        .init(kind: "positional", name: "query", short: nil, required: true,
                              repeating: false, summary: "Terms.", defaultValue: nil, values: nil),
                        .init(kind: "option", name: "--limit", short: "-n", required: false,
                              repeating: false, summary: "Max.", defaultValue: "20", values: nil),
                        .init(kind: "option", name: "--sort", short: nil, required: false,
                              repeating: false, summary: "Order.", defaultValue: "relevance",
                              values: ["relevance", "date"]),
                        .init(kind: "option", name: "--fields", short: nil, required: false,
                              repeating: true, summary: "Fields.", defaultValue: nil, values: nil),
                        .init(kind: "flag", name: "--full", short: nil, required: false,
                              repeating: false, summary: "All.", defaultValue: nil, values: nil),
                        .init(kind: "flag", name: "--text", short: nil, required: false,
                              repeating: false, summary: "Text.", defaultValue: nil, values: nil),
                    ]
                ),
                Manifest.Command(
                    path: ["channel", "videos"], invocation: "yt-fetch channel videos",
                    summary: "Uploads.", details: nil,
                    arguments: [
                        .init(kind: "positional", name: "channel", short: nil, required: true,
                              repeating: false, summary: "A channel.", defaultValue: nil, values: nil)
                    ]
                ),
                Manifest.Command(
                    path: ["batch"], invocation: "yt-fetch batch",
                    summary: "Several at once.", details: nil,
                    arguments: [
                        .init(kind: "positional", name: "urls", short: nil, required: false,
                              repeating: true, summary: "URLs.", defaultValue: nil, values: nil)
                    ]
                ),
                // The protocol machinery is in the manifest — describe readers
                // want the full tree — but must never be advertised as a tool.
                Manifest.Command(
                    path: ["describe"], invocation: "yt-fetch describe",
                    summary: "The manifest.", details: nil, arguments: []
                ),
                Manifest.Command(
                    path: ["mcp"], invocation: "yt-fetch mcp",
                    summary: "This server.", details: nil, arguments: []
                ),
            ]
        )
    }

    /// Records the argv it was called with and returns a canned result.
    private final class Recorder: @unchecked Sendable {
        var argv: [String] = []
        var result = MCPServer.CommandResult(stdout: "{\"ok\":true}", stderr: "", exitCode: 0)
    }

    private func server(_ recorder: Recorder = Recorder()) -> (MCPServer, Recorder) {
        let server = MCPServer(manifest: manifest()) { args in
            recorder.argv = args
            return recorder.result
        }
        return (server, recorder)
    }

    private func send(_ json: String, to server: MCPServer) throws -> [String: Any]? {
        guard let data = server.handle(Data(json.utf8)) else { return nil }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Handshake

    func testInitializeAdvertisesToolsAndServerInfo() throws {
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#, to: server))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])

        XCTAssertEqual(reply["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(result["protocolVersion"] as? String, MCPServer.protocolVersion)
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "yt-fetch")
    }

    func testInitializeEchoesASupportedClientVersion() throws {
        // A strict client may drop the session when offered a revision it did
        // not ask for; echoing one this server can honestly speak avoids that.
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            to: server
        ))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
    }

    func testInitializeFallsBackForAnUnknownClientVersion() throws {
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2030-01-01"}}"#,
            to: server
        ))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, MCPServer.protocolVersion)
    }

    func testNotificationsGetNoReply() throws {
        // A message without an id is a notification; replying to one is a
        // protocol violation.
        let (server, _) = self.server()
        XCTAssertNil(server.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)))
    }

    func testPingIsAnswered() throws {
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send(#"{"jsonrpc":"2.0","id":9,"method":"ping"}"#, to: server))
        XCTAssertNotNil(reply["result"])
    }

    func testUnknownMethodReturnsMethodNotFound() throws {
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send(#"{"jsonrpc":"2.0","id":1,"method":"nope"}"#, to: server))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testMalformedJSONReturnsParseError() throws {
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send("{not json", to: server))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    // MARK: - tools/list

    private func tools(from server: MCPServer) throws -> [[String: Any]] {
        let reply = try XCTUnwrap(send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#, to: server))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        return try XCTUnwrap(result["tools"] as? [[String: Any]])
    }

    func testRootCommandIsNotExposedAsATool() throws {
        // The root dispatches to subcommands and does nothing on its own.
        let (server, _) = self.server()
        XCTAssertEqual(try tools(from: server).count, 3)
    }

    func testProtocolCommandsAreNotExposedAsTools() throws {
        // An agent offered `yt-fetch_mcp` will eventually call it, and a
        // server nested inside a server blocks on a stream that is already
        // spoken for. `describe` is the manifest the client already has.
        let (server, _) = self.server()
        let names = try tools(from: server).compactMap { $0["name"] as? String }
        XCTAssertFalse(names.contains("yt-fetch_mcp"))
        XCTAssertFalse(names.contains("yt-fetch_describe"))
    }

    func testUnexposedCommandsCannotBeCalledEither() throws {
        // tools/call must agree with tools/list, or a client that guesses the
        // name still nests a server.
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"yt-fetch_mcp","arguments":{}}}"#,
            to: server
        ))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testToolNamesAreProtocolLegal() throws {
        let (server, _) = self.server()
        for tool in try tools(from: server) {
            let name = try XCTUnwrap(tool["name"] as? String)
            XCTAssertFalse(name.isEmpty)
            XCTAssertLessThanOrEqual(name.count, 64)
            XCTAssertTrue(
                name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" },
                "illegal character in \(name)"
            )
        }
    }

    func testNestedPathBecomesOneToolName() {
        XCTAssertEqual(
            MCPServer.toolName(tool: "yt-fetch", path: ["channel", "videos"]),
            "yt-fetch_channel_videos"
        )
    }

    func testToolNameSanitisesIllegalCharactersAndClamps() {
        XCTAssertEqual(MCPServer.toolName(tool: "a.b", path: ["c d"]), "a_b_c_d")
        XCTAssertLessThanOrEqual(
            MCPServer.toolName(tool: String(repeating: "x", count: 80), path: ["y"]).count, 64
        )
    }

    // MARK: - Input Schema

    private func schema(for invocation: String) -> [String: Any] {
        let command = manifest().commands.first { $0.invocation == invocation }!
        return MCPServer.inputSchema(for: command)
    }

    func testRequiredListsOnlyRequiredArguments() throws {
        let s = schema(for: "yt-fetch search")
        XCTAssertEqual(s["required"] as? [String], ["query"])
    }

    func testPositionalAndOptionNamesDropTheirDashes() throws {
        let props = try XCTUnwrap(schema(for: "yt-fetch search")["properties"] as? [String: Any])
        XCTAssertNotNil(props["query"])
        XCTAssertNotNil(props["limit"])
        XCTAssertNil(props["--limit"])
    }

    func testEnumOptionCarriesItsPermittedValues() throws {
        let props = try XCTUnwrap(schema(for: "yt-fetch search")["properties"] as? [String: Any])
        let sort = try XCTUnwrap(props["sort"] as? [String: Any])
        XCTAssertEqual(sort["type"] as? String, "string")
        XCTAssertEqual(sort["enum"] as? [String], ["relevance", "date"])
    }

    func testNumericDefaultImpliesAnIntegerType() throws {
        let props = try XCTUnwrap(schema(for: "yt-fetch search")["properties"] as? [String: Any])
        let limit = try XCTUnwrap(props["limit"] as? [String: Any])
        XCTAssertEqual(limit["type"] as? String, "integer")
        XCTAssertEqual(limit["default"] as? Int, 20)
    }

    func testFlagIsBooleanAndRepeatingIsAnArray() throws {
        let props = try XCTUnwrap(schema(for: "yt-fetch search")["properties"] as? [String: Any])
        XCTAssertEqual((props["full"] as? [String: Any])?["type"] as? String, "boolean")
        XCTAssertEqual((props["fields"] as? [String: Any])?["type"] as? String, "array")
    }

    func testFormatFlagsAreNotExposedOverMCP() throws {
        // The transport always wants the piped default; offering --text invites
        // an agent to request prose it then has to parse.
        let props = try XCTUnwrap(schema(for: "yt-fetch search")["properties"] as? [String: Any])
        XCTAssertNil(props["text"])
        XCTAssertNil(props["json"])
    }

    // MARK: - tools/call

    private func call(_ name: String, _ arguments: String, on server: MCPServer) throws -> [String: Any] {
        let json = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
        let reply = try XCTUnwrap(send(json, to: server))
        return try XCTUnwrap(reply["result"] as? [String: Any])
    }

    func testCallBuildsTheArgumentVector() throws {
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        _ = try call("yt-fetch_search", #"{"query":"swift 6","limit":5,"sort":"date","full":true}"#, on: server)

        XCTAssertEqual(recorder.argv.first, "search")
        XCTAssertEqual(recorder.argv[1], "swift 6", "positional must come first")
        XCTAssertTrue(recorder.argv.contains("--limit"))
        XCTAssertTrue(recorder.argv.contains("5"))
        XCTAssertTrue(recorder.argv.contains("--sort"))
        XCTAssertTrue(recorder.argv.contains("date"))
        XCTAssertTrue(recorder.argv.contains("--full"))
    }

    func testNestedCommandPathIsExpanded() throws {
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        _ = try call("yt-fetch_channel_videos", #"{"channel":"@iJustine"}"#, on: server)
        XCTAssertEqual(recorder.argv, ["channel", "videos", "@iJustine"])
    }

    func testFalseFlagIsOmittedEntirely() throws {
        // `--full false` is not something ArgumentParser understands.
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        _ = try call("yt-fetch_search", #"{"query":"x","full":false}"#, on: server)
        XCTAssertFalse(recorder.argv.contains("--full"))
    }

    func testRepeatingOptionEmitsOneFlagPerValue() throws {
        // ArgumentParser's default for an array option is `.singleValue`, so
        // `--fields title url` binds only "title" and spills "url" into a
        // positional slot. Repeated pairs parse the same under both parsing
        // strategies.
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        _ = try call("yt-fetch_search", #"{"query":"x","fields":["title","url"]}"#, on: server)
        let index = try XCTUnwrap(recorder.argv.firstIndex(of: "--fields"))
        XCTAssertEqual(Array(recorder.argv[index...]), ["--fields", "title", "--fields", "url"])
    }

    func testRepeatingPositionalFlattensItsElements() throws {
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        _ = try call("yt-fetch_batch", #"{"urls":["one","two"]}"#, on: server)
        XCTAssertEqual(recorder.argv, ["batch", "one", "two"])
    }

    func testNullOptionValuesAreTreatedAsOmitted() throws {
        // JSON null is how an agent says "unset" — it must not become the
        // literal string "<null>" on the command line.
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        _ = try call("yt-fetch_search", #"{"query":"x","limit":null,"sort":null,"full":null}"#, on: server)
        XCTAssertEqual(recorder.argv, ["search", "x"])
    }

    func testNullRequiredPositionalIsRejectedBeforeRunning() throws {
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        let reply = try XCTUnwrap(send(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"yt-fetch_search","arguments":{"query":null}}}"#,
            to: server
        ))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertTrue(recorder.argv.isEmpty, "must not run the command")
    }

    func testEmptyRepeatingOptionIsOmitted() throws {
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        _ = try call("yt-fetch_search", #"{"query":"x","fields":[]}"#, on: server)
        XCTAssertFalse(recorder.argv.contains("--fields"))
    }

    func testSuccessfulCallReturnsStdoutAndIsNotAnError() throws {
        let recorder = Recorder()
        recorder.result = .init(stdout: #"{"videoId":"abc"}"#, stderr: "", exitCode: 0)
        let (server, _) = self.server(recorder)

        let result = try call("yt-fetch_search", #"{"query":"x"}"#, on: server)
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, #"{"videoId":"abc"}"#)
    }

    func testFailedCallSurfacesTheErrorEnvelopeAsContent() throws {
        // The stderr envelope carries the hint that lets a caller repair itself,
        // so it must reach the model — not be swallowed as a transport fault.
        let recorder = Recorder()
        recorder.result = .init(
            stdout: "",
            stderr: #"{"error":{"code":"not_found","hint":"retry with --lang"}}"#,
            exitCode: 1
        )
        let (server, _) = self.server(recorder)

        let result = try call("yt-fetch_search", #"{"query":"x"}"#, on: server)
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text.contains("retry with --lang"))
    }

    func testMissingRequiredArgumentIsRejectedBeforeRunning() throws {
        let recorder = Recorder()
        let (server, _) = self.server(recorder)

        let reply = try XCTUnwrap(send(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"yt-fetch_search","arguments":{}}}"#,
            to: server
        ))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertTrue(recorder.argv.isEmpty, "must not run the command")
    }

    func testUnknownToolIsRejected() throws {
        let (server, _) = self.server()
        let reply = try XCTUnwrap(send(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#,
            to: server
        ))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testEveryListedToolCanBeCalledBack() throws {
        // tools/list and tools/call must agree on names, or the server
        // advertises tools it then rejects.
        let (server, _) = self.server()
        for tool in try tools(from: server) {
            let name = try XCTUnwrap(tool["name"] as? String)
            let reply = try XCTUnwrap(send(
                #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"\#(name)","arguments":{"query":"x","channel":"y"}}}"#,
                to: server
            ))
            XCTAssertNil(reply["error"], "advertised tool \(name) was rejected")
        }
    }
}
