//
//  XDG.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Resolving the XDG base directories the cache and the credential store
//  live under. One implementation, because the two resolving it separately
//  is how they end up disagreeing about where "home" is.
//

import Foundation

/// XDG base-directory resolution.
enum XDG {

    /// The directory a base-directory variable names, or the fallback.
    ///
    /// The specification requires these paths to be absolute and says a
    /// relative one "should be considered invalid and ignored" — honouring it
    /// would scatter caches and credentials relative to whatever directory
    /// the tool happened to run from.
    static func directory(_ value: String?, or fallback: @autoclosure () -> URL) -> URL {
        guard let value, value.hasPrefix("/") else { return fallback() }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
