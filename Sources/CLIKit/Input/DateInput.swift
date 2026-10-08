//
//  DateInput.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  What `--since` and `--until` take, read the same way in every tool.
//

import Foundation

/// A date as somebody types it at a prompt.
///
/// `2026-01-31`, `2026-01` or `2026` — the start of that day, month or year —
/// or a span back from now: `7d`, `3w`, `6m`, `1y`. The relative forms are the
/// ones people actually type; a tool that takes only ISO dates makes somebody
/// open a calendar to ask "what came in last week".
///
/// One grammar for the whole fleet, because an agent that learned `inbox
/// search --since 7d` should not discover that `imessage` wants something
/// else. Both tools carried their own copy of this until 0.8.0.
public enum DateInput {

    /// Reads a date.
    ///
    /// - Parameters:
    ///   - value: What was typed.
    ///   - now: The moment relative spans count back from. Injected so tests
    ///     do not depend on the clock.
    ///   - calendar: The calendar dates are read in — the user's, by default,
    ///     so `2026-01-31` means midnight here rather than in UTC.
    /// - Throws: ``CLIError`` with ``CLIError/Code/usage`` for anything else.
    public static func parse(_ value: String, now: Date = Date(), calendar: Calendar = .current) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()

        if let unit = trimmed.last, "dwmy".contains(unit),
           let count = Int(trimmed.dropLast()), count >= 0 {
            let component: Calendar.Component = switch unit {
            case "d": .day
            case "w": .weekOfYear
            case "m": .month
            default: .year
            }
            guard let date = calendar.date(byAdding: component, value: -count, to: now) else {
                throw CLIError.usage("cannot go back \(value)")
            }
            return date
        }

        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard (1...3).contains(parts.count), numbers.count == parts.count, parts[0].count == 4 else {
            throw CLIError.usage("\(value) is not a date", hint: "write it as 2026-01-31, 2026-01 or 2026, or as 7d, 3w, 6m, 1y")
        }

        var components = DateComponents()
        components.year = numbers[0]
        components.month = numbers.count > 1 ? numbers[1] : 1
        components.day = numbers.count > 2 ? numbers[2] : 1

        // `isValidDate` refuses 2026-02-30 rather than rolling it into March,
        // which is what `date(from:)` alone would do — a typo that silently
        // becomes a different date.
        guard let date = calendar.date(from: components),
              components.isValidDate(in: calendar) else {
            throw CLIError.usage("\(value) is not a date")
        }
        return date
    }
}
