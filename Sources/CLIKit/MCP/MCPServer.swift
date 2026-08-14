//
//  MCPServer.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A Model Context Protocol server over stdio, generated from the tool's own
//  manifest so the exposed tools cannot drift from the commands that exist.
//
//  Message handling is a pure function of the request, with command execution
//  injected — the transport loop is the only part that touches the world.
//

import Foundation

/// Serves a tool's commands over MCP.
public struct MCPServer: Sendable {

    // MARK: Types

    /// The outcome of running one command.
    public struct CommandResult: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32

        public init(stdout: String, stderr: String, exitCode: Int32) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }
    }

    /// Runs the tool with the given argument vector.
    public typealias Runner = @Sendable ([String]) -> CommandResult

    // MARK: Properties

    /// The command tree being exposed.
    public let manifest: Manifest

    /// The MCP protocol revision this server speaks.
    public static let protocolVersion = "2024-11-05"

    private let run: Runner

    // MARK: Initialisation

    public init(manifest: Manifest, run: @escaping Runner) {
        self.manifest = manifest
        self.run = run
    }

    // MARK: Message Handling

    /// Handles one JSON-RPC message.
    ///
    /// - Returns: The reply, or `nil` for a notification (which by protocol
    ///   must not be answered).
    public func handle(_ message: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else {
            return encode(error: -32700, message: "Parse error", id: nil)
        }

        let id = object["id"]
        guard let method = object["method"] as? String else {
            return encode(error: -32600, message: "Invalid request", id: id)
        }

        // Notifications carry no id and must never receive a reply.
        if id == nil {
            return nil
        }

        switch method {
        case "initialize":
            return encode(result: [
                "protocolVersion": Self.protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": manifest.tool, "version": manifest.version],
            ], id: id)

        case "ping":
            return encode(result: [String: Any](), id: id)

        case "tools/list":
            return encode(result: ["tools": toolDefinitions()], id: id)

        case "tools/call":
            let params = object["params"] as? [String: Any] ?? [:]
            return callTool(params: params, id: id)

        default:
            return encode(error: -32601, message: "Method not found: \(method)", id: id)
        }
    }

    // MARK: Tool Definitions

    /// One MCP tool per invocable command.
    func toolDefinitions() -> [[String: Any]] {
        manifest.commands.compactMap { command in
            // The root command dispatches to subcommands and does nothing alone.
            guard !command.path.isEmpty else { return nil }

            return [
                "name": Self.toolName(tool: manifest.tool, path: command.path),
                "description": Self.description(of: command),
                "inputSchema": Self.inputSchema(for: command),
            ]
        }
    }

    /// A protocol-legal tool name: `[a-zA-Z0-9_-]{1,64}`.
    static func toolName(tool: String, path: [String]) -> String {
        let raw = ([tool] + path).joined(separator: "_")
        let sanitised = String(raw.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
        return String(sanitised.prefix(64))
    }

    /// The description an agent reads when choosing a tool.
    static func description(of command: Manifest.Command) -> String {
        var text = command.summary ?? "Run `\(command.invocation)`."
        if let details = command.details {
            text += "\n\n" + details
        }
        text += "\n\nInvoked as: \(command.invocation)"
        return text
    }

    /// A JSON Schema describing the command's arguments.
    static func inputSchema(for command: Manifest.Command) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for argument in command.arguments where !Manifest.formatArguments.contains(argument.name) {
            let key = Self.propertyName(for: argument)
            var schema: [String: Any] = [:]

            if let summary = argument.summary {
                schema["description"] = summary
            }

            if argument.kind == "flag" {
                schema["type"] = "boolean"
            } else if argument.repeating {
                schema["type"] = "array"
                schema["items"] = ["type": "string"]
            } else if let values = argument.values {
                schema["type"] = "string"
                schema["enum"] = values
            } else if let defaultValue = argument.defaultValue, Int(defaultValue) != nil {
                // A numeric default is the only signal available that an option
                // takes a number; the dump carries no type information.
                schema["type"] = "integer"
            } else {
                schema["type"] = "string"
            }

            if let defaultValue = argument.defaultValue {
                schema["default"] = Int(defaultValue) ?? (defaultValue as Any)
            }

            properties[key] = schema
            if argument.required { required.append(key) }
        }

        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    /// The JSON property name for an argument — its name without dashes.
    static func propertyName(for argument: Manifest.Argument) -> String {
        argument.name.hasPrefix("--") ? String(argument.name.dropFirst(2)) : argument.name
    }

    // MARK: Tool Invocation

    private func callTool(params: [String: Any], id: Any?) -> Data? {
        guard let name = params["name"] as? String else {
            return encode(error: -32602, message: "Missing tool name", id: id)
        }
        guard let command = manifest.commands.first(where: {
            !$0.path.isEmpty && Self.toolName(tool: manifest.tool, path: $0.path) == name
        }) else {
            return encode(error: -32602, message: "Unknown tool: \(name)", id: id)
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let argv: [String]
        do {
            argv = try Self.argumentVector(for: command, arguments: arguments)
        } catch let error as CLIError {
            return encode(error: -32602, message: error.message, id: id)
        } catch {
            return encode(error: -32602, message: "\(error)", id: id)
        }

        let result = run(argv)

        // A failure is reported as tool content with isError, not a JSON-RPC
        // error: the caller wants the structured envelope on stderr — it carries
        // the hint that lets it repair itself — not a transport-level fault.
        let succeeded = result.exitCode == 0
        let text = succeeded
            ? result.stdout
            : (result.stderr.nilIfEmpty ?? "exit \(result.exitCode)")

        return encode(result: [
            "content": [["type": "text", "text": text]],
            "isError": !succeeded,
        ], id: id)
    }

    /// Builds the argument vector for a command from an MCP arguments object.
    static func argumentVector(
        for command: Manifest.Command,
        arguments: [String: Any]
    ) throws -> [String] {
        var argv = command.path

        // Positionals must precede options and keep their declared order. Once
        // one is omitted argv has no way to express a later one — its value
        // would bind to the earlier slot — so a gap must end the list.
        var positionalGap: String?
        for argument in command.arguments where argument.kind == "positional" {
            let key = propertyName(for: argument)
            guard let value = arguments[key] else {
                if argument.required {
                    throw CLIError.usage("Missing required argument '\(key)'")
                }
                positionalGap = key
                continue
            }
            if let gap = positionalGap {
                throw CLIError.usage("Argument '\(key)' also needs '\(gap)' — positionals cannot be skipped")
            }
            argv.append(stringify(value))
        }

        // Format flags are hidden from the tool schema (the subprocess pipes
        // stdout, so it already resolves to JSON); ignoring them here keeps the
        // executor honest to what the schema advertises.
        for argument in command.arguments
        where argument.kind != "positional" && !Manifest.formatArguments.contains(argument.name) {
            let key = propertyName(for: argument)
            guard let value = arguments[key] else { continue }

            if argument.kind == "flag" {
                // Only pass the flag when true; passing `--flag false` is not a
                // thing ArgumentParser understands.
                if let enabled = value as? Bool, enabled { argv.append(argument.name) }
                continue
            }

            if let list = value as? [Any] {
                guard !list.isEmpty else { continue }
                argv.append(argument.name)
                argv.append(contentsOf: list.map(stringify))
            } else {
                argv.append(argument.name)
                argv.append(stringify(value))
            }
        }

        return argv
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let bool as Bool: return bool ? "true" : "false"
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        default: return String(describing: value)
        }
    }

    // MARK: Encoding

    private func encode(result: [String: Any], id: Any?) -> Data? {
        envelope(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func encode(error code: Int, message: String, id: Any?) -> Data? {
        envelope([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ])
    }

    private func envelope(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    // MARK: Transport

    /// Reads newline-delimited JSON-RPC from stdin until EOF, replying on stdout.
    ///
    /// Nothing else may write to stdout while this runs — it is the protocol
    /// channel. Diagnostics belong on stderr.
    public func serve() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let reply = handle(Data(line.utf8)) else { continue }

            FileHandle.standardOutput.write(reply)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
