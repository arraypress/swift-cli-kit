//
//  SecurePrompt.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Reading a secret from a person without echoing it or leaving it anywhere.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reads secrets from standard input without echoing them.
///
/// Secrets are never accepted as command-line arguments. An argument is visible
/// in `ps` for the lifetime of the process and is written verbatim into shell
/// history, so `tmdb-meta auth login --api-key sk_live_…` would leak the value
/// twice over. Prompting and `--stdin` are the only supported paths.
public enum SecurePrompt {

    /// Prompts on standard error and reads a line from standard input with
    /// terminal echo disabled.
    ///
    /// The prompt goes to stderr so that stdout carries only real output, which
    /// keeps `auth login` safe to pipe like every other subcommand.
    ///
    /// - Parameter prompt: The text shown before the cursor.
    /// - Returns: The entered text, or `nil` on EOF.
    public static func readSecret(_ prompt: String) -> String? {
        guard isatty(FileHandle.standardInput.fileDescriptor) == 1 else {
            // Not a terminal — there is no echo to suppress and no person to
            // prompt. Read the pipe.
            return readLine(strippingNewline: true)
        }

        FileHandle.standardError.write(Data(prompt.utf8))

        var original = termios()
        guard tcgetattr(FileHandle.standardInput.fileDescriptor, &original) == 0 else {
            // Cannot control the terminal; better to read with echo than to
            // refuse outright.
            let value = readLine(strippingNewline: true)
            Terminal.writeError("")
            return value
        }

        var muted = original
        muted.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(FileHandle.standardInput.fileDescriptor, TCSAFLUSH, &muted)

        let value = readLine(strippingNewline: true)

        tcsetattr(FileHandle.standardInput.fileDescriptor, TCSAFLUSH, &original)
        // The user's newline was swallowed along with the echo.
        Terminal.writeError("")

        return value
    }

    /// Reads a whole line from standard input, trimming surrounding whitespace.
    ///
    /// Used for `--stdin`, where the caller is a script piping a value in. The
    /// trim matters because `echo "$KEY" | …` appends a newline that would
    /// otherwise be stored as part of the secret.
    public static func readPipedSecret() -> String? {
        guard let line = readLine(strippingNewline: true) else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
