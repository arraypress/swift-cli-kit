//
//  ConditionallyActing.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A command that acts only with some of its flags.
//

import Foundation

/// A command declared acting that, with some arguments, only reads —
/// `files 4821` lists attachments, `files 4821 --save ~/Desktop` writes them.
///
/// Its ``EffectDeclaring/commandEffect`` stays the worst case — that is what
/// `describe` and the MCP hints show, since they describe the command, not
/// one run of it — but `--read-only` lets a run through when ``actsThisRun``
/// is false, as it lets a ``MutatingCommand``'s `--dry-run` through.
public protocol ConditionallyActing: EffectDeclaring {

    /// Whether this run, as parsed, would change anything.
    var actsThisRun: Bool { get }
}
