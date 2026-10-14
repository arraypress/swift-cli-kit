//
//  ChildProcessError.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why ``ChildProcess`` returned no ``ChildOutput``. A child that ran and
/// failed is not an error here — its status is in the output.
public enum ChildProcessError: Error, Equatable, Sendable, CLIErrorConvertible {

    /// The executable could not be started (missing, not executable…).
    case couldNotStart(executable: String, reason: String)

    /// The task was cancelled; the child was stopped and reaped first.
    case cancelled

    public var cliErrorCode: CLIError.Code { .upstream }

    /// What went wrong, without the executable's name.
    public var reason: String {
        switch self {
        case .couldNotStart(_, let reason): reason
        case .cancelled: "cancelled"
        }
    }
}

extension ChildProcessError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .couldNotStart(let executable, let reason): "could not run \(executable): \(reason)"
        case .cancelled: "cancelled"
        }
    }
}
