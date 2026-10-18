//
//  UntrustedContent.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A payload naming which of its fields hold text other people wrote.
//

import Foundation

/// A payload with fields that carry text written by someone other than the
/// user — a message body, an email subject, a sender's display name, a note,
/// a fetched page.
///
/// The ``Emitter`` wraps the string values of these keys in
/// `<<untrusted:TOKEN>>…<</untrusted:TOKEN>>` whenever the run's
/// ``UntrustedPolicy`` is on, so an agent reading the output can tell data
/// from instructions. Keys match at any depth — name the nested ones too — and
/// a key whose value is an array of strings has each string wrapped. Only
/// strings are touched: an id, a date or a number under a listed key passes
/// through unchanged, and a key not listed is never wrapped, so list free text
/// only.
///
/// ```swift
/// extension Message: @retroactive UntrustedContent {
///     public static let untrustedFields: Set<String> = ["text", "subject"]
/// }
/// ```
///
/// Text output is the payload's own: call ``Untrusted/text(_:)`` on those
/// same fields inside `renderText()` and `tableRow`.
public protocol UntrustedContent {

    /// The JSON keys whose string values another person wrote.
    static var untrustedFields: Set<String> { get }
}
