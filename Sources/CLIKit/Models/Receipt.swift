//
//  Receipt.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  What a command actually changed, as a fact rather than a sentence.
//
//  THE DIFFERENCE THAT MATTERS. A tool that prints "deleted note 718" has told you its last
//  statement ran. It has not told you the note is gone. That gap is not hypothetical: a
//  delete in this family reported success, exited zero, and left the note exactly where it
//  was — twice. A receipt is the other thing: a record of subjects and states that a caller
//  can go and check, and that a later command can read.
//
//  SO EVERY CHANGE NAMES ITS SUBJECT. Not "3 files updated" but which three, by an identifier
//  the same tool will accept back — a path, an id, a name. A receipt whose subjects cannot be
//  looked up again is a sentence with extra punctuation.
//
//  THERE IS NO UNDO HERE, and that is deliberate rather than unfinished. Most of what these
//  tools do is not reversible: an overwritten note body is gone, a deleted folder is in
//  Recently Deleted for thirty days and then is not. An undo that works most of the time is
//  MORE dangerous than none, because it invites a trust it cannot earn. What a receipt does
//  instead is record enough for a person to decide, and to put things back by hand if they
//  choose to.
//

import Foundation

/// One thing that changed.
public struct Change: Codable, Equatable, Hashable, Sendable {

    /// What happened to it.
    public enum Kind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        case created
        case updated
        case deleted
        case moved
        case renamed
        /// Considered and left alone. Worth recording: "nothing to do" and "did nothing by
        /// mistake" look identical in a log that omits it.
        case unchanged

        /// What a plan says it will do — "would **delete** x".
        ///
        /// The raw value is the past tense, which is right for a receipt and wrong for a
        /// plan: "would deleted x" is what you get without this.
        var future: String {
            switch self {
            case .created: return "create"
            case .updated: return "update"
            case .deleted: return "delete"
            case .moved: return "move"
            case .renamed: return "rename"
            case .unchanged: return "leave alone"
            }
        }
    }

    public let kind: Kind

    /// What changed, named so the same tool would accept it back — a path, an id, a name.
    public let subject: String

    /// What it was, where that is meaningful. The old folder for a move, the old name for a
    /// rename. `nil` for a create.
    public let from: String?

    /// What it became. `nil` for a delete.
    public let to: String?

    /// Anything else worth recording, as plain strings so it encodes anywhere.
    public let detail: [String: String]

    public init(_ kind: Kind, subject: String, from: String? = nil, to: String? = nil,
                detail: [String: String] = [:]) {
        self.kind = kind
        self.subject = subject
        self.from = from
        self.to = to
        self.detail = detail
    }

    /// A line a person can read.
    ///
    /// - Parameter future: whether this is something that will happen rather than something
    ///   that did, which decides the tense of the verb.
    public func summary(future: Bool = false) -> String {
        let verb = future ? kind.future : kind.rawValue
        switch (from, to) {
        case let (from?, to?): return "\(verb) \(subject): \(from) → \(to)"
        case let (nil, to?): return "\(verb) \(subject) → \(to)"
        case let (from?, nil): return "\(verb) \(subject) (was \(from))"
        case (nil, nil): return "\(verb) \(subject)"
        }
    }

    /// A line a person can read, in the past tense.
    public var summary: String { summary() }
}

/// What a command did, or would do.
public struct Receipt: Codable, Equatable, Sendable {

    /// The tool that issued it — `notes`, `img`.
    public let tool: String

    /// The verb — `delete`, `convert`.
    public let action: String

    /// When. ISO 8601, so it sorts as text and parses anywhere.
    public let at: String

    /// Whether this is a plan or a record.
    ///
    /// The same shape either way ON PURPOSE: a caller reads one format, and a plan can be
    /// diffed against the receipt that follows it to see whether the tool did what it said.
    public let planned: Bool

    public let changes: [Change]

    public init(tool: String, action: String, planned: Bool, changes: [Change],
                at: Date = Date()) {
        self.tool = tool
        self.action = action
        self.planned = planned
        self.changes = changes
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.at = formatter.string(from: at)
    }

    /// How many changed, tallied by kind. `unchanged` is not counted as a change.
    public var counts: [Change.Kind: Int] {
        changes.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    /// Whether anything actually moved.
    public var isEmpty: Bool { changes.allSatisfy { $0.kind == .unchanged } }
}
