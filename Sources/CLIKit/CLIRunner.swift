//
//  CLIRunner.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The entry point every tool in the family uses instead of `@main` on the
//  root command.
//
//  It exists for one reason. ArgumentParser exits **64** when it cannot parse
//  the arguments — the BSD `sysexits.h` value for a usage error. Our published
//  contract says usage errors are **2**, and `CLIError.usage` thrown from
//  inside a command does exit 2. So a tool answered the same mistake with two
//  different codes depending on which layer happened to notice it:
//
//      readable page.html --extract widgets   # our check      → 2
//      readable page.html --nonsense          # the parser's   → 64
//
//  A caller branching on `$?` cannot be expected to know where the check
//  lives. Exit codes are the one thing this family promises to keep stable, so
//  the parser's code is remapped onto ours rather than the other way round —
//  2 is what `describe --json`, every README and `CLIExitCode` already say.
//

import ArgumentParser
import Foundation

/// Runs a root command, normalising ArgumentParser's exit codes onto
/// ``CLIExitCode``.
public enum CLIRunner {

    /// Parses, dispatches and exits. Never returns.
    ///
    /// Replaces the `main()` that `@main` would synthesise:
    ///
    /// ```swift
    /// @main
    /// enum Main {
    ///     static func main() async { await CLIRunner.run(YTFetchCommand.self) }
    /// }
    /// ```
    public static func run<Root: ParsableCommand>(_ root: Root.Type) async -> Never {
        do {
            var command = try root.parseAsRoot()

            // Mirrors AsyncParsableCommand.main(): a subcommand may be either
            // kind, and running an async one synchronously would skip its body.
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            exit(CLIExitCode.ok.rawValue)
        } catch {
            // A CLIError thrown by a subcommand that is not a ``CLICommand``
            // (auth, describe, mcp) would otherwise fall through to
            // ArgumentParser's generic handler — struct dump, exit 1 — and
            // break the exit-code contract those commands document.
            if let cliError = error as? CLIError {
                exit(Emitter.report(cliError).rawValue)
            }

            // `--help` and `--version` arrive here as CleanExit and belong on
            // stdout with code 0; only genuine parse failures are remapped.
            if root.exitCode(for: error) == ExitCode.validationFailure {
                let message = root.fullMessage(for: error)
                if !message.isEmpty {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                }
                exit(CLIExitCode.usage.rawValue)
            }
            root.exit(withError: error)
        }
    }
}
