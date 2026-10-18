//
//  RetryVerdict.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Whether doing it again is safe — said by the tool, which knows, rather than
//  guessed by the caller, which does not.
//
//  WHY IT EXISTS. An agent whose `send` timed out has two bad choices without
//  this: retry and risk a duplicate message, or give up on one that never left.
//  The tool knows which side of the line the failure fell on — the script never
//  started, or it started and then stopped answering — so it says so.
//

import Foundation

/// Whether an action that failed, or may not have finished, is safe to repeat.
///
/// Raw values are snake_case and part of the public contract: they appear
/// verbatim as `"retry"` in receipts and in the JSON error envelope.
public enum RetryVerdict: String, Codable, Equatable, Hashable, Sendable, CaseIterable {

    /// Nothing was attempted — refused, invalid, or failed before it reached
    /// the thing it acts on. Safe to retry once the cause is fixed.
    case notStarted = "not_started"

    /// Started and still under way, or accepted but not yet confirmed (a
    /// message queued for delivery). Do not retry: check again later.
    case inFlight = "in_flight"

    /// Started, then the outcome was lost — a timeout, a crash, an answer that
    /// never came. It may well have happened. Check before retrying.
    case mayHaveCompleted = "may_have_completed"

    /// Done and confirmed. Retrying would do it a second time.
    case completed

    /// Whether repeating the action blindly is safe.
    public var isSafeToRetry: Bool { self == .notStarted }

    /// A line a person can read.
    public var summary: String {
        switch self {
        case .notStarted: "not started — safe to retry"
        case .inFlight: "in flight — do not retry; check again shortly"
        case .mayHaveCompleted: "may have completed — check before retrying"
        case .completed: "completed — retrying would do it again"
        }
    }

    /// How strongly this verdict argues against a blind retry, for folding
    /// several into one: any doubt outranks any certainty.
    var caution: Int {
        switch self {
        case .notStarted: 0
        case .completed: 1
        case .inFlight: 2
        case .mayHaveCompleted: 3
        }
    }

    /// The most cautious of several verdicts, or `nil` when there are none.
    public static func combined<S: Sequence>(_ verdicts: S) -> RetryVerdict? where S.Element == RetryVerdict {
        verdicts.max { $0.caution < $1.caution }
    }
}
