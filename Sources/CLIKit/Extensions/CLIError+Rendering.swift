//
//  CLIError+Rendering.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The model's two derived forms — the JSON envelope and the human
//  line. Every rule lives in Output/ErrorRendering; this delegates.
//

import Foundation

extension CLIError {

    /// The JSON envelope written to stderr in machine mode.
    ///
    /// Shape is fixed:
    /// ```json
    /// {"error":{"code":"auth_required","service":"tmdb","message":"…","hint":"…"}}
    /// ```
    var jsonEnvelope: String {
        ErrorRendering.envelope(code: code.rawValue, message: message, service: service, hint: hint)
    }

    /// The human-readable form, used when stderr is a terminal.
    var humanDescription: String {
        ErrorRendering.human(message: message, hint: hint)
    }
}
