//
//  MutatingCommand.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A command that changes something, and says what before and after.
//
//  THE SHAPE IS PLAN THEN APPLY, and the split has to be real: ``plan()`` works out what
//  would change WITHOUT changing it, and ``apply(_:)`` does it. A conformer that quietly does
//  the work in `plan()` breaks `--dry-run` for everybody, which is the one promise this type
//  makes.
//
//  WHY A PROTOCOL AND NOT A CONVENTION. Every tool here had already grown its own half of
//  this by hand — one printed a warning naming a count, another printed a line on success,
//  a third asked for `--yes`. All of it reinvented per file, none of it machine-readable, and
//  none of it checkable. This is that, once.
//
//  NO UNDO, deliberately. See ``Receipt`` for why.
//

import ArgumentParser
import Foundation

/// A command that changes something.
public protocol MutatingCommand: CLICommand {

    /// The verb, for the receipt — `delete`, `convert`, `move`.
    static var actionName: String { get }

    var common: CommonOptions { get }
    var write: WriteOptions { get }

    /// Whether this run should stop after planning.
    ///
    /// Defaults to `--dry-run`. A tool whose policy is "show it unless confirmed" — `dupe
    /// delete` acts only with `--yes` — overrides this so the shared flow still governs,
    /// rather than growing a second dry run beside the first.
    var isPlanOnly: Bool { get }

    /// What this WOULD change. Must not change anything.
    ///
    /// Called for a dry run and for a real one both, so the plan a caller is shown is the
    /// same plan that gets applied rather than a description of it.
    func plan() async throws -> [Change]

    /// Do it.
    ///
    /// - Parameter plan: what ``plan()`` worked out.
    /// - Returns: what actually changed. Usually the plan, but not always: a tool that finds
    ///   a subject already gone should return it as `.unchanged` rather than claim a delete.
    func apply(_ plan: [Change]) async throws -> [Change]
}

public extension MutatingCommand {

    var isPlanOnly: Bool { write.dryRun }

    /// Plan, apply unless asked not to, and emit the receipt.
    func execute() async throws {
        let planned = try await plan()

        if isPlanOnly {
            let receipt = Receipt(tool: Self.serviceID, action: Self.actionName,
                                  planned: true, changes: planned)
            try write.save(receipt, service: Self.serviceID)
            try common.emitter.emit(ReceiptPayload(receipt))
            return
        }

        let applied = try await apply(planned)
        let receipt = Receipt(tool: Self.serviceID, action: Self.actionName,
                              planned: false, changes: applied)
        // Saved BEFORE emitting: if writing the receipt fails, the caller finds out rather
        // than seeing a success line and an empty file.
        try write.save(receipt, service: Self.serviceID)
        try common.emitter.emit(ReceiptPayload(receipt))
    }
}

/// A receipt on its way out.
public struct ReceiptPayload: Encodable, TextRenderable {

    public let tool: String
    public let action: String
    public let at: String
    /// True when nothing was done because `--dry-run` was passed.
    public let planned: Bool
    public let changes: [Change]

    public init(_ receipt: Receipt) {
        tool = receipt.tool
        action = receipt.action
        at = receipt.at
        planned = receipt.planned
        changes = receipt.changes
    }

    public func renderText() -> String {
        guard !changes.isEmpty else {
            return planned ? "\(action): nothing to do" : "\(action): nothing changed"
        }
        return changes.map {
            planned ? "would " + $0.summary(future: true) : $0.summary
        }.joined(separator: "\n")
    }
}
