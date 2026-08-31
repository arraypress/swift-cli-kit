//
//  ErrorRendering.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  How a failure becomes bytes on stderr, and how a foreign error is
//  classified into one. Both are rules, not shape, so they live here as
//  pure functions — the JSON escaping especially, which is hand-rolled
//  so that error reporting has no failure path of its own, and is
//  exactly the kind of rule that deserves tests constructing no error.
//

import Foundation

/// Rendering and classification rules for ``CLIError``.
enum ErrorRendering {

    /// The JSON envelope written to stderr in machine mode.
    static func envelope(code: String, message: String, service: String?, hint: String?) -> String {
        var fields: [String] = [
            "\"code\":\(quoted(code))",
            "\"message\":\(quoted(message))",
        ]
        if let service { fields.append("\"service\":\(quoted(service))") }
        if let hint { fields.append("\"hint\":\(quoted(hint))") }
        return "{\"error\":{\(fields.joined(separator: ","))}}"
    }

    /// The human-readable form, used when stderr is a terminal.
    static func human(message: String, hint: String?) -> String {
        var out = "error: \(message)"
        if let hint { out += "\n  hint: \(hint)" }
        return out
    }

    /// Classifies an arbitrary error onto the right ``CLIError`` code.
    /// Anything unrecognised becomes upstream — transient by assumption,
    /// because telling a caller to retry a permanent failure is a cheaper
    /// mistake than telling it to give up on a temporary one.
    static func classify(_ error: Error, service: String?) -> CLIError {
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

    /// Minimal JSON string escaping. Hand-rolled rather than routed
    /// through `JSONEncoder` so that error reporting cannot itself throw.
    static func quoted(_ value: String) -> String {
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
