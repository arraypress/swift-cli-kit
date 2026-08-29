//
//  XDG.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Resolving the XDG base directories the cache, the credential store and
//  every tool's own saved state live under. One implementation, because two
//  resolving it separately is how they end up disagreeing about where "home"
//  is — and a tool that reads `XDG_CONFIG_HOME` its own way is the one whose
//  profile a test run writes into somebody's real config directory.
//

import Foundation

/// XDG base-directory resolution.
public enum XDG {

    /// `$XDG_CONFIG_HOME`, or `~/.config`.
    ///
    /// Where a tool keeps what it was told: credentials, a saved profile.
    /// Append the family namespace and the tool's own directory to it.
    public static var configHome: URL {
        directory(
            ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
            or: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        )
    }

    /// `$XDG_CACHE_HOME`, or `~/.cache`.
    ///
    /// Where a tool keeps what it can fetch again. Anything under it may be
    /// deleted at any time, and a tool must carry on as if it never existed.
    public static var cacheHome: URL {
        directory(
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"],
            or: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache", isDirectory: true)
        )
    }

    /// The directory a base-directory variable names, or the fallback.
    ///
    /// The specification requires these paths to be absolute and says a
    /// relative one "should be considered invalid and ignored" — honouring it
    /// would scatter caches and credentials relative to whatever directory
    /// the tool happened to run from. An empty value is ignored the same way.
    public static func directory(_ value: String?, or fallback: @autoclosure () -> URL) -> URL {
        guard let value, value.hasPrefix("/") else { return fallback() }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
