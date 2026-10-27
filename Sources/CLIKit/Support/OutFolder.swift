//
//  OutFolder.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  An option that takes a FOLDER for the results, given a FILE name.
//
//  `--out clip.mp4` on a tool whose `--out` is a folder used to create a
//  folder called clip.mp4, put the result inside it, and exit 0 — success
//  over the wrong thing. vid caught it first (0.12.0); img, caption, master
//  and design had it too, each in its own shape. The rule lives here once.
//

import ArgumentParser
import Foundation

/// The check for an option that names a folder for results.
///
/// A name ending in a file extension — `clip.mp4`, `cover.png`, `words.srt`
/// — is refused unless a folder by that name really exists, with a message
/// that points at the option that names a file. Run it from `validate()`, so
/// every command with the option gets it and the refusal exits 2 (usage).
public enum OutFolder {

    /// Extensions that name files, never folders: the media, document and
    /// data names people type. Lowercase, without the dot.
    public static let fileExtensions: Set<String> = [
        // video
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "mpg", "mpeg", "3gp", "mts",
        // audio
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "ogg", "opus",
        // images
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp", "avif", "psd", "svg",
        // documents, subtitles, data
        "pdf", "srt", "vtt", "json", "csv", "txt", "md", "zip",
    ]

    /// Why `path` cannot be the folder that was meant, or `nil` when it can.
    ///
    /// Pure: whether the path is an existing folder is passed in, so every
    /// rule is testable without touching the disk.
    ///
    /// - Parameters:
    ///   - path: What was typed for the folder option.
    ///   - isFolder: Whether a folder already exists at `path`. An existing
    ///     folder is always accepted, whatever it is called.
    ///   - option: The folder option's spelling, for the message (`--out`).
    ///   - fileOption: The option that names ONE file, when the command has
    ///     one (`-o`); `nil` when it has none.
    ///   - alsoNames: The extension the folder option itself accepts as a
    ///     single file name, when it does double duty (`-o out.mp4` names the
    ///     file, `-o clips` the folder); a name ending in it is accepted.
    ///   - fileExtensions: The extensions that make a name a file name.
    /// - Returns: A message for the caller, saying what to type instead.
    public static func problem(
        _ path: String,
        isFolder: Bool,
        option: String = "--out",
        fileOption: String? = "-o",
        alsoNames: String? = nil,
        fileExtensions: Set<String> = OutFolder.fileExtensions
    ) -> String? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        guard !isFolder, fileExtensions.contains(ext) else { return nil }
        if let alsoNames {
            let wanted = alsoNames.lowercased()
            guard ext != wanted else { return nil }
            let renamed = (name as NSString).deletingPathExtension + "." + wanted
            return "\(option) is a folder for the results or, for one input, the .\(wanted) file itself, and \(name) is neither: name it \(renamed), or give \(option) a folder name."
        }
        if let fileOption {
            return "\(option) is a folder for the results, and \(name) is a file name: to name the file, use \(fileOption) \(path); with several inputs, give \(option) a folder name."
        }
        return "\(option) is a folder for the results, and \(name) is a file name: give \(option) a folder name."
    }

    /// Whether a folder exists at `path`, after expanding a leading `~`.
    public static func isFolder(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path.expandedPath, isDirectory: &directory) && directory.boolValue
    }

    /// Refuses `path` as a folder when it is a file name — the call for a
    /// `validate()`. Nothing given, nothing to check.
    ///
    /// - Throws: `ValidationError`, which ArgumentParser reports with the
    ///   usage line and exit 2.
    public static func check(
        _ path: String?,
        option: String = "--out",
        fileOption: String? = "-o",
        alsoNames: String? = nil,
        fileExtensions: Set<String> = OutFolder.fileExtensions
    ) throws {
        guard let path else { return }
        if let message = problem(path, isFolder: isFolder(path), option: option, fileOption: fileOption,
                                 alsoNames: alsoNames, fileExtensions: fileExtensions) {
            throw ValidationError(message)
        }
    }
}
