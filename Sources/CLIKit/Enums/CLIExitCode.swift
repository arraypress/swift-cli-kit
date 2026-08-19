//
//  CLIExitCode.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Stable process exit codes shared by every tool built on CLIKit.
//

import Foundation

/// The exit codes every CLIKit-based tool returns.
///
/// These are a **public contract**. Automated callers — agents, scripts, CI —
/// branch on the number rather than parsing prose from stderr, so the mapping
/// must stay stable across versions: append new cases, never renumber existing
/// ones.
///
/// ```sh
/// yt-meta transcript "$URL" || case $? in
///   1) echo "no transcript for this video" ;;
///   4) sleep 60 ;;   # rate limited, back off
///   6) echo "extractor is broken, upgrade yt-meta" ;;
/// esac
/// ```
///
/// A closed pipe is part of the contract too: when the downstream reader stops
/// early — `tool … | head -1` — the run ends with ``ok``, not with the shell's
/// 141. ``CLIRunner`` ignores SIGPIPE and ``Terminal`` treats the resulting
/// EPIPE on stdout as "the caller has what it wanted".
public enum CLIExitCode: Int32, Sendable, CaseIterable {

    /// The command succeeded.
    case ok = 0

    /// The request was well-formed but the resource does not exist.
    ///
    /// Distinct from ``parseFailure``: the service answered, and the answer was
    /// "no such thing".
    case notFound = 1

    /// The arguments were invalid — unknown flag, missing operand, bad value.
    case usage = 2

    /// A credential is required and was not found.
    ///
    /// The accompanying error carries a `hint` naming the exact command that
    /// fixes it, so a caller can self-repair rather than stall.
    case authRequired = 3

    /// The upstream service rejected the request for rate-limiting reasons.
    ///
    /// Callers should back off and retry; the request itself was valid.
    case rateLimited = 4

    /// The upstream service or the network failed — DNS, timeout, 5xx, TLS.
    ///
    /// Transient by assumption. Retrying later is reasonable.
    case upstream = 5

    /// The service responded, but its payload no longer matches what the
    /// extractor expects.
    ///
    /// This almost always means the site changed its markup or private API and
    /// the library needs updating. Separating it from ``notFound`` matters: it
    /// tells a caller "this tool is broken" rather than "your input was wrong",
    /// and it is the signal worth alerting on when a scraper rots.
    case parseFailure = 6
}
