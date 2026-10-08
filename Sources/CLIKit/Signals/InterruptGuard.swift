//
//  InterruptGuard.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Dispatch
import Foundation

/// An armed Ctrl-C handler, from ``Interrupt/onFirst(secondExits:_:)``.
public final class InterruptGuard: @unchecked Sendable {

    private let source: DispatchSourceSignal
    private let latch = SignalLatch()

    init(secondExits: Bool, handler: @escaping @Sendable () -> Void) {
        signal(SIGINT, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue(label: "clikit.interrupt.guard"))
        source.setEventHandler { [latch] in
            if latch.trip() {
                handler()
            } else if secondExits {
                exit(130)
            }
        }
        source.resume()
    }

    /// Puts Ctrl-C back to killing the process.
    public func remove() {
        source.cancel()
        signal(SIGINT, SIG_DFL)
    }
}
