//
//  StreamDrain.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Reads one pipe as data arrives, through `readabilityHandler` — never
//  `FileHandle.bytes`. Foundation serves every `bytes` sequence in a process
//  from one serial queue with blocking reads, so two of them read
//  concurrently (stdout and stderr) take turns: a quiet stderr held the queue
//  while a trainer's stdout sat unread for half an hour (imagine train,
//  2026-10-14). Each `readabilityHandler` is its own dispatch source; one
//  stream cannot hold up the other.
//

import Foundation
import os

/// Drains one output pipe: keeps what ``ChildCapture`` asks for and hands
/// each line to a callback, in order.
final class StreamDrain: Sendable {

    private struct Buffer {
        var data = Data()
        var tail: [String] = []
        var splitter = LineSplitter()
        var finished = false
    }

    private let buffer = OSAllocatedUnfairLock(initialState: Buffer())
    private let capture: ChildCapture
    private let line: (@Sendable (String) -> Void)?

    init(capture: ChildCapture, line: (@Sendable (String) -> Void)?) {
        self.capture = capture
        self.line = line
    }

    /// Whether lines have to be split out at all.
    private var splitsLines: Bool {
        if line != nil { return true }
        if case .lastLines = capture { return true }
        return false
    }

    /// Starts reading `handle`; `ended` runs once, at end of stream.
    func attach(_ handle: FileHandle, ended: @escaping @Sendable () -> Void) {
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            let atEnd = chunk.isEmpty
            if atEnd { handle.readabilityHandler = nil }
            let lines = take(atEnd ? nil : chunk)
            if let line, let lines { for text in lines { line(text) } }
            if atEnd { ended() }
        }
    }

    /// Stops reading early (a grandchild holding the pipe open), keeping
    /// what has arrived.
    func detach(_ handle: FileHandle) {
        handle.readabilityHandler = nil
        buffer.withLock { $0.finished = true }
    }

    /// What was kept, for the result.
    var kept: Data {
        buffer.withLock { buffer in
            switch capture {
            case .all: buffer.data
            case .none: Data()
            case .lastLines: Data(buffer.tail.joined(separator: "\n").utf8)
            }
        }
    }

    /// Takes in a chunk (or, with `nil`, the end of the stream) and returns
    /// the lines it completed — `nil` when nothing needs them.
    private func take(_ chunk: Data?) -> [String]? {
        let lines: [String]? = buffer.withLock { buffer in
            guard !buffer.finished else { return nil }
            var lines: [String] = []
            if let chunk {
                if capture == .all { buffer.data.append(chunk) }
                guard splitsLines else { return nil }
                lines = buffer.splitter.feed(chunk)
            } else {
                buffer.finished = true
                guard splitsLines, let last = buffer.splitter.finish() else { return nil }
                lines = [last]
            }
            if case .lastLines(let count) = capture {
                buffer.tail.append(contentsOf: lines)
                if buffer.tail.count > count { buffer.tail.removeFirst(buffer.tail.count - max(count, 0)) }
            }
            return lines
        }
        guard line != nil else { return nil }
        return lines
    }
}
