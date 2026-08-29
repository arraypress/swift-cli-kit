//
//  JSONEncoder+Readable.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension JSONEncoder {

    /// The encoder for a file a person may open: sorted keys, pretty-printed,
    /// slashes left alone.
    ///
    /// Piped output stays compact — a caller paying by the token gets no
    /// whitespace — but a credentials file, a saved profile or a config on
    /// disk is read by people as often as by tools, and sorted keys mean two
    /// saves of the same thing produce the same bytes, so a diff shows the
    /// change and nothing else.
    ///
    /// A fresh instance each time: `JSONEncoder` is a class with settings,
    /// and a shared one is a shared mutable thing.
    static var readable: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }
}
