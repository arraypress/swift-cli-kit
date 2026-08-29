//
//  SecureFile.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Writing a file that only its owner may read. The credential store needs
//  it for secrets; a résumé tool needs it for a saved profile that is
//  somebody's address and date of birth. The shape is the same and the
//  mistakes are the same, so it is written once.
//

import Foundation

/// A file written at mode `0600`, in a directory created at `0700`.
public enum SecureFile {

    /// Writes `data` to `url`, readable only by its owner, from the first byte.
    ///
    /// The replacement is created with restrictive permissions and then moved
    /// into place. Writing the real file directly and tightening it afterwards
    /// leaves a window in which the contents sat on disk at the umask default
    /// — short, but a window nonetheless, and this is the file for the things
    /// that must not have one.
    ///
    /// The parent directory is created at `0700` when it does not exist. An
    /// existing directory's mode is left alone: it is the caller's, and a
    /// library quietly changing it is worse than the looser mode.
    ///
    /// - Throws: ``CLIError`` with ``CLIError/Code/upstream`` when the
    ///   directory cannot be created or the file cannot be written.
    public static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()

        if !manager.fileExists(atPath: directory.path) {
            do {
                try manager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw CLIError.upstream("Could not create \(directory.path): \(error.localizedDescription)")
            }
        }

        let temporary = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        guard manager.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CLIError.upstream("Could not write to \(directory.path)")
        }

        do {
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
                // replaceItemAt can carry the original's attributes over.
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw CLIError.upstream("Could not write \(url.path): \(error.localizedDescription)")
        }
    }

    /// Writes `value` as JSON the way the family writes its own files —
    /// sorted keys, pretty-printed — readable only by its owner.
    ///
    /// A file somebody may open in an editor to fix by hand is written so
    /// that they can: one key per line, in an order that does not move
    /// between saves.
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data: Data
        do {
            data = try JSONEncoder.readable.encode(value)
        } catch {
            throw CLIError.upstream("Could not encode \(url.lastPathComponent): \(error.localizedDescription)")
        }
        try write(data, to: url)
    }
}
