//
//  CLIError.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A machine-readable error type. Every failure a CLIKit tool reports carries a
//  stable code, a human message, and — where one exists — a hint naming the
//  command that fixes it.
//

import Foundation

/// A failure that can be rendered for both humans and machines.
///
/// The `hint` field is the important one for automated callers. An agent that
/// receives `auth_required` with `hint: "run: tmdb-meta auth login"` can repair
/// itself; one that receives only "unauthorized" stalls and asks a human.
public struct CLIError: Error, Sendable {

    /// The stable, machine-readable reason for the failure.
    ///
    /// Raw values are snake_case and form part of the public contract — they
    /// appear verbatim in the JSON error envelope.
    public enum Code: String, Sendable, CaseIterable {
        case notFound = "not_found"
        case usage = "usage"
        case authRequired = "auth_required"
        case rateLimited = "rate_limited"
        case upstream = "upstream"
        case parseFailure = "parse_failure"

        /// The process exit code this reason maps to.
        public var exitCode: CLIExitCode {
            switch self {
            case .notFound: return .notFound
            case .usage: return .usage
            case .authRequired: return .authRequired
            case .rateLimited: return .rateLimited
            case .upstream: return .upstream
            case .parseFailure: return .parseFailure
            }
        }
    }

    /// Why the command failed.
    public let code: Code

    /// A one-line human-readable description. No trailing period.
    public let message: String

    /// A concrete next action, ideally a runnable command.
    public let hint: String?

    /// The service the failure relates to, e.g. `"youtube"`.
    public let service: String?

    public init(
        code: Code,
        message: String,
        hint: String? = nil,
        service: String? = nil
    ) {
        self.code = code
        self.message = message
        self.hint = hint
        self.service = service
    }
}

// MARK: - Convenience Constructors

public extension CLIError {

    /// The resource does not exist.
    static func notFound(_ message: String, service: String? = nil, hint: String? = nil) -> CLIError {
        CLIError(code: .notFound, message: message, hint: hint, service: service)
    }

    /// The arguments were invalid.
    static func usage(_ message: String, hint: String? = nil) -> CLIError {
        CLIError(code: .usage, message: message, hint: hint)
    }

    /// A credential is missing.
    ///
    /// Prefer ``CredentialResolver/require(_:)``, which builds this with a hint
    /// naming the tool's own login command.
    static func authRequired(_ message: String, service: String? = nil, hint: String? = nil) -> CLIError {
        CLIError(code: .authRequired, message: message, hint: hint, service: service)
    }

    /// The service is rate limiting us.
    static func rateLimited(_ message: String, service: String? = nil, retryAfter: Int? = nil) -> CLIError {
        let hint = retryAfter.map { "retry after \($0)s" } ?? "back off and retry"
        return CLIError(code: .rateLimited, message: message, hint: hint, service: service)
    }

    /// The network or the upstream service failed.
    static func upstream(_ message: String, service: String? = nil, hint: String? = nil) -> CLIError {
        CLIError(code: .upstream, message: message, hint: hint, service: service)
    }

    /// The response no longer matches what the extractor expects.
    static func parseFailure(_ message: String, service: String? = nil, tool: String? = nil) -> CLIError {
        let hint = tool.map { "the extractor may be out of date — try: brew upgrade \($0)" }
        return CLIError(code: .parseFailure, message: message, hint: hint, service: service)
    }
}

// MARK: - Mapping Foreign Errors

public extension CLIError {

    /// Wraps an arbitrary error, mapping well-known network failures onto the
    /// right code so callers still get a meaningful exit status.
    ///
    /// Anything unrecognised becomes ``Code/upstream`` — transient by
    /// assumption, because telling a caller to retry a permanent failure is a
    /// cheaper mistake than telling it to give up on a temporary one.
    ///
    /// - Parameters:
    ///   - error: The underlying error.
    ///   - service: The service being contacted, for the envelope.
    static func wrapping(_ error: Error, service: String? = nil) -> CLIError {
        if let cliError = error as? CLIError { return cliError }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                return .upstream("Network unreachable: \(urlError.localizedDescription)", service: service)
            case .timedOut:
                return .upstream("Request timed out", service: service, hint: "retry")
            case .badServerResponse, .cannotParseResponse:
                return .upstream("Malformed response from server", service: service)
            default:
                return .upstream(urlError.localizedDescription, service: service)
            }
        }

        if error is DecodingError {
            return .parseFailure("Could not decode the service response", service: service)
        }

        return .upstream(error.localizedDescription, service: service)
    }
}

// MARK: - Rendering

extension CLIError {

    /// The JSON envelope written to stderr in machine mode.
    ///
    /// Shape is fixed:
    /// ```json
    /// {"error":{"code":"auth_required","service":"tmdb","message":"…","hint":"…"}}
    /// ```
    var jsonEnvelope: String {
        var fields: [String] = [
            "\"code\":\(Self.quote(code.rawValue))",
            "\"message\":\(Self.quote(message))",
        ]
        if let service { fields.append("\"service\":\(Self.quote(service))") }
        if let hint { fields.append("\"hint\":\(Self.quote(hint))") }
        return "{\"error\":{\(fields.joined(separator: ","))}}"
    }

    /// The human-readable form, used when stderr is a terminal.
    var humanDescription: String {
        var out = "error: \(message)"
        if let hint { out += "\n  hint: \(hint)" }
        return out
    }

    /// Minimal JSON string escaping.
    ///
    /// Hand-rolled rather than routed through `JSONEncoder` so that error
    /// reporting has no failure path of its own — a throwing encoder in the
    /// error handler would be a bad place to discover a bug.
    private static func quote(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }
}
