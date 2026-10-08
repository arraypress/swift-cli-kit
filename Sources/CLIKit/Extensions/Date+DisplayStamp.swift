//
//  Date+DisplayStamp.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension Date {

    /// `2026-10-08 14:22` in this Mac's time zone.
    ///
    /// Sortable, and the same day for every reader — which `08/10/2026` is
    /// not. Built from date components rather than a shared `DateFormatter`,
    /// which is mutable state behind a value-type façade. Four tools carried
    /// their own copy of exactly this until 0.8.0.
    var displayStamp: String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: self)
        return String(format: "%04d-%02d-%02d %02d:%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}
