//
//  String+Counted.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension String {

    /// The noun counted: `"page".counted(1)` is `1 page`, `"page".counted(3)`
    /// is `3 pages`.
    ///
    /// A summary line says how many of something it made, and every tool
    /// writes the `s` conditional inline — six times in one of them, with
    /// the same expression each time. The plural is the noun with an `s`
    /// unless one is given, which covers `entries` and `matches`.
    ///
    /// - Parameters:
    ///   - count: How many.
    ///   - plural: The plural form, when it is not the noun plus `s`.
    func counted(_ count: Int, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? self : plural ?? self + "s")"
    }
}
