//
//  Interrupt.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Ctrl-C, taken over. A tool that records, holds an assertion or listens
//  must not simply die on SIGINT: an unfinalised movie is unplayable, a
//  dictation in progress has text worth keeping, a watch has a tally worth
//  printing. Five tools each wrote this by hand, in three shapes; these are
//  the two that cover all of them.
//

import Dispatch
import Foundation

/// Turns SIGINT (and, for a wait, SIGTERM) into something a command handles.
public enum Interrupt {

    /// What ended a ``wait(timeout:)``.
    public enum Ended: Sendable, Equatable {
        /// Ctrl-C, or a polite `kill`.
        case interrupted
        /// The timeout passed first.
        case timedOut
    }

    /// Waits until Ctrl-C or SIGTERM, or until `timeout` seconds pass.
    ///
    /// Both signals stay ignored afterwards, on purpose: the caller is about
    /// to finalise something — a movie, a report — and a second Ctrl-C
    /// during that would destroy the very thing the first asked to keep.
    /// Dispatch signal sources resuming a continuation: genuinely async, no
    /// run-loop pumping.
    ///
    /// - Parameter timeout: Seconds to wait at most; `nil` waits for a signal.
    /// - Returns: Which came first.
    public static func wait(timeout: Double? = nil) async -> Ended {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Ended, Never>) in
            let latch = SignalLatch()
            let queue = DispatchQueue(label: "clikit.interrupt.wait")
            let sources = [SIGINT, SIGTERM].map { DispatchSource.makeSignalSource(signal: $0, queue: queue) }
            latch.keep(sources)
            for source in sources {
                source.setEventHandler {
                    if latch.trip() { continuation.resume(returning: .interrupted) }
                }
                source.resume()
            }
            if let timeout {
                queue.asyncAfter(deadline: .now() + timeout) {
                    if latch.trip() { continuation.resume(returning: .timedOut) }
                }
            }
        }
    }

    /// Runs `handler` on the first Ctrl-C instead of dying.
    ///
    /// The handler runs on its own queue, not inside the signal handler
    /// proper, so it may take locks and write output — and it still runs
    /// when the command is busy on the main thread, as a polling loop is. A second Ctrl-C exits
    /// at once with 130 (128 + SIGINT, the shell convention) unless
    /// `secondExits` is false — the escape hatch when the graceful stop hangs.
    ///
    /// - Returns: The guard; call ``InterruptGuard/remove()`` to give Ctrl-C
    ///   back. Keep it alive for as long as the handler should stay armed.
    public static func onFirst(
        secondExits: Bool = true,
        _ handler: @escaping @Sendable () -> Void
    ) -> InterruptGuard {
        InterruptGuard(secondExits: secondExits, handler: handler)
    }
}
