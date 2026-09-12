//
//  WriteOptions.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The flags every command that CHANGES something shares.
//
//  Separate from ``CommonOptions`` because `--dry-run` on a listing is meaningless, and a
//  flag that means nothing on half the commands teaches a caller to ignore it. A tool adds
//  this group only to the verbs that write.
//

import ArgumentParser
import Foundation

/// Flags every mutating CLIKit command accepts.
public struct WriteOptions: ParsableArguments {

    public init() {}

    @Flag(name: .long, help: "Say what would change, and change nothing.")
    public var dryRun: Bool = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Write the receipt here as JSON.",
            discussion: "A record of what changed, by subject, that a caller can check against."
        )
    )
    public var receipt: String?

    /// Write the receipt out, if asked for.
    ///
    /// - Throws: ``CLIError/upstream(_:service:)`` if the file cannot be written — a receipt
    ///   that silently failed to save is worse than one that was never requested, because
    ///   the caller believes they have a record.
    public func save(_ receipt: Receipt, service: String) throws {
        guard let path = self.receipt else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: url, options: .atomic)
        } catch {
            throw CLIError.upstream("Could not write the receipt to \(path): \(error.localizedDescription)",
                                    service: service)
        }
    }
}
