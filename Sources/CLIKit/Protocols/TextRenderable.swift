//
//  TextRenderable.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A payload that can present itself to a person.
//

import Foundation

/// A result type that can render itself for human consumption.
///
/// Every payload a CLIKit tool emits conforms to this alongside `Encodable`, so
/// the emitter can serve both audiences from one value.
public protocol TextRenderable {

    /// A compact, terminal-friendly rendering. No trailing newline.
    func renderText() -> String
}
