//
//  UntrustedJSON.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Wrapping declared fields inside encoded JSON, touching nothing else.
//
//  WHY A SCANNER AND NOT JSONSerialization. Re-serialising through Foundation
//  rewrites numbers — 0.1 comes back as 0.10000000000000001 — and would make
//  wrapping change values it was never asked to touch. This walks the encoded
//  bytes once, rewrites only the string values under the declared keys, and
//  copies every other byte as it was: key order, spacing and numbers intact.
//

import Foundation

/// Wraps the string values of named keys inside encoded JSON.
enum UntrustedJSON {

    private enum Frame {
        case object(key: String?, expectingKey: Bool)
        case array(owner: String?)
    }

    /// `json` with every string value under a key in `fields` — directly, or
    /// as an element of an array under it — wrapped with `policy`.
    static func wrap(_ json: Data, fields: Set<String>, policy: UntrustedPolicy) -> Data {
        guard policy.isEnabled, !fields.isEmpty else { return json }

        let bytes = [UInt8](json)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 8)
        var stack: [Frame] = []
        var index = 0

        func owner() -> String? {
            switch stack.last {
            case .object(let key, _)?: key
            case .array(let owner)?: owner
            case nil: nil
            }
        }

        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case quote:
                let end = endOfString(bytes, from: index)
                let token = bytes[index..<end]
                if case .object(_, true)? = stack.last {
                    stack[stack.count - 1] = .object(key: decode(token), expectingKey: false)
                    out.append(contentsOf: token)
                } else if let key = owner(), fields.contains(key),
                          let value = decode(token), !value.isEmpty,
                          let encoded = encode(policy.apply(value)) {
                    out.append(contentsOf: encoded)
                } else {
                    out.append(contentsOf: token)
                }
                index = end
                continue
            case openBrace:
                stack.append(.object(key: nil, expectingKey: true))
            case openBracket:
                stack.append(.array(owner: owner()))
            case closeBrace, closeBracket:
                _ = stack.popLast()
            case comma:
                if case .object(let key, _)? = stack.last {
                    stack[stack.count - 1] = .object(key: key, expectingKey: true)
                }
            default:
                break
            }
            out.append(byte)
            index += 1
        }
        return Data(out)
    }

    // MARK: - Tokens

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let openBrace = UInt8(ascii: "{")
    private static let closeBrace = UInt8(ascii: "}")
    private static let openBracket = UInt8(ascii: "[")
    private static let closeBracket = UInt8(ascii: "]")
    private static let comma = UInt8(ascii: ",")

    /// The index just past the closing quote of the string starting at `start`.
    private static func endOfString(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start + 1
        while index < bytes.count {
            if bytes[index] == backslash { index += 2; continue }
            if bytes[index] == quote { return index + 1 }
            index += 1
        }
        return bytes.count
    }

    /// A string token's value. Unescaped text — nearly every key — is read
    /// directly; anything with an escape goes through the decoder.
    private static func decode(_ token: ArraySlice<UInt8>) -> String? {
        guard token.count >= 2 else { return nil }
        let inner = token.dropFirst().dropLast()
        if !inner.contains(backslash) { return String(decoding: inner, as: UTF8.self) }
        return try? JSONDecoder().decode(String.self, from: Data(token))
    }

    private static func encode(_ value: String) -> [UInt8]? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { [UInt8]($0) }
    }
}
