//
//  SignalLatch.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Dispatch
import Foundation

/// Fires once, from whichever signal or timer gets there first, and keeps
/// the signal sources alive until then — a source that is deallocated stops
/// delivering. The one mutable flag is behind a lock, which never spans an
/// await.
final class SignalLatch: @unchecked Sendable {

    private let lock = NSLock()
    private var fired = false
    private var kept: [any DispatchSourceProtocol] = []

    /// Holds sources for the latch's lifetime.
    func keep(_ sources: [any DispatchSourceProtocol]) {
        lock.lock(); defer { lock.unlock() }
        kept.append(contentsOf: sources)
    }

    /// `true` the first time only.
    func trip() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
