//
//  KeepAwakeToken.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation
import os

/// A held "keep the Mac awake" assertion, from ``KeepAwake/hold(_:)``.
///
/// Released by ``release()`` or when the token is deallocated, whichever
/// comes first; releasing twice is harmless.
public final class KeepAwakeToken: Sendable {

    /// The assertion, or `nil` once it has been given back.
    private let id: OSAllocatedUnfairLock<UInt32?>

    private let assertions: any PowerAssertions

    init(id: UInt32, assertions: any PowerAssertions) {
        self.id = OSAllocatedUnfairLock(initialState: id)
        self.assertions = assertions
    }

    /// Lets the Mac sleep again.
    public func release() {
        let held = id.withLock { state -> UInt32? in
            defer { state = nil }
            return state
        }
        if let held { assertions.release(held) }
    }

    deinit { release() }
}
