//
//  CLICommand.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The base command type. Maps a thrown ``CLIError`` onto the right exit code
//  and envelope, so the mapping cannot drift between tools.
//

import ArgumentParser
import Foundation

/// A subcommand that reports failures through the shared error contract.
///
/// Conformers implement ``execute()`` and throw ``CLIError``. The default
/// ``run()`` catches it, writes the envelope to stderr, and exits with the
/// matching ``CLIExitCode`` — so no individual command has to remember the
/// mapping, and the mapping cannot drift between tools.
public protocol CLICommand: AsyncParsableCommand {

    /// The service this command talks to, e.g. `"youtube"`. Used to tag errors.
    static var serviceID: String { get }

    /// The command body.
    func execute() async throws
}

public extension CLICommand {

    func run() async throws {
        do {
            try await execute()
        } catch let error as ExitCode {
            throw error
        } catch let error as ValidationError {
            // Rethrown so ArgumentParser prints its usage block; ``CLIRunner``
            // is what turns the parser's exit 64 into our documented 2.
            throw error
        } catch {
            let cliError = CLIError.wrapping(error, service: Self.serviceID)
            let code = Emitter.report(cliError)
            throw ExitCode(code.rawValue)
        }
    }
}
