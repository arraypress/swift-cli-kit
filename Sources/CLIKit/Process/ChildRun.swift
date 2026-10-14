//
//  ChildRun.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  One running child: both pipes drained as data arrives, stdin fed from its
//  own thread, a timeout and a stop that escalate to SIGKILL, and one
//  completion once the child has exited AND both streams have ended.
//
//  Nothing here reads after waiting: a child blocks as soon as it has written
//  a pipe buffer's worth (64 KB) that nobody reads, so `waitUntilExit()`
//  before reading — or reading stdout to its end before stderr — deadlocks
//  the moment the output is big enough.
//

import Foundation
import os

/// A started child process and the bookkeeping that finishes it.
final class ChildRun: Sendable {

    /// Why the child was stopped before it ended on its own.
    enum Stop: Sendable { case timedOut, cancelled }

    private struct State {
        var exited = false
        var openStreams = 2
        var stop: Stop?
        var finished = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    let process: Process
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let done = DispatchSemaphore(value: 0)
    private let out: StreamDrain
    private let err: StreamDrain
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let input: Data?

    /// How long to wait for the streams to end once the child has exited.
    /// They end at once unless a grandchild inherited them and lives on.
    private let drainGrace: Double

    /// How long a stopped child gets between SIGTERM and SIGKILL.
    private let killGrace: Double

    init(
        executable: URL, arguments: [String], environment: [String: String]?, directory: URL?,
        input: Data?, stdout: ChildCapture, stderr: ChildCapture,
        onStdout: (@Sendable (String) -> Void)?, onStderr: (@Sendable (String) -> Void)?,
        drainGrace: Double, killGrace: Double
    ) {
        process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let directory { process.currentDirectoryURL = directory }
        out = StreamDrain(capture: stdout, line: onStdout)
        err = StreamDrain(capture: stderr, line: onStderr)
        self.input = input
        self.drainGrace = drainGrace
        self.killGrace = killGrace
    }

    /// Launches the child and starts draining it.
    func start(timeout: Double?) throws(ChildProcessError) {
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Never the parent's stdin: under MCP that is the protocol channel,
        // and a child reading it would eat frames or block on them forever.
        let inPipe = input.map { _ in Pipe() }
        process.standardInput = inPipe ?? FileHandle.nullDevice

        out.attach(outPipe.fileHandleForReading) { [self] in streamEnded() }
        err.attach(errPipe.fileHandleForReading) { [self] in streamEnded() }
        process.terminationHandler = { [weak self] _ in self?.exited() }
        do {
            try process.run()
        } catch {
            out.detach(outPipe.fileHandleForReading)
            err.detach(errPipe.fileHandleForReading)
            throw .couldNotStart(executable: process.executableURL?.path ?? "?", reason: error.localizedDescription)
        }

        if let input, let writer = inPipe?.fileHandleForWriting {
            // A child that exits without reading must not SIGPIPE us.
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            // Its own thread: written here, a large input would block while
            // the child blocks writing output nobody is reading yet.
            DispatchQueue.global().async {
                try? writer.write(contentsOf: input)
                try? writer.close()
            }
        }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.stop(.timedOut) }
        }
    }

    /// Stops the child: SIGTERM, then SIGKILL if it lingers.
    func stop(_ reason: Stop) {
        let first = state.withLock { state -> Bool in
            guard !state.exited, state.stop == nil else { return false }
            state.stop = reason
            return true
        }
        guard first else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + killGrace) { [weak self] in
            guard let self, !state.withLock({ $0.exited }) else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// Why the child was stopped, if it was.
    var stopReason: Stop? { state.withLock { $0.stop } }

    /// Blocks until the run is finished.
    func waitBlocking() {
        done.wait()
        done.signal()
    }

    /// Suspends until the run is finished.
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finished = state.withLock { state -> Bool in
                if !state.finished { state.waiters.append(continuation) }
                return state.finished
            }
            if finished { continuation.resume() }
        }
    }

    /// The output, once finished.
    var output: ChildOutput {
        ChildOutput(
            status: process.terminationStatus,
            signalled: process.terminationReason == .uncaughtSignal,
            timedOut: stopReason == .timedOut,
            stdout: out.kept,
            stderr: err.kept
        )
    }

    // MARK: - Finishing

    private func streamEnded() {
        state.withLock { $0.openStreams -= 1 }
        finishIfDone(force: false)
    }

    private func exited() {
        state.withLock { $0.exited = true }
        // Both streams normally end within moments of the exit; a grandchild
        // that inherited them may keep them open for ever, and is not waited for.
        DispatchQueue.global().asyncAfter(deadline: .now() + drainGrace) { [weak self] in self?.finishIfDone(force: true) }
        finishIfDone(force: false)
    }

    private func finishIfDone(force: Bool) {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>]? in
            guard !state.finished, state.exited, force || state.openStreams <= 0 else { return nil }
            state.finished = true
            defer { state.waiters.removeAll() }
            return state.waiters
        }
        guard let waiters else { return }
        if force {
            out.detach(outPipe.fileHandleForReading)
            err.detach(errPipe.fileHandleForReading)
        }
        done.signal()
        for waiter in waiters { waiter.resume() }
    }
}
