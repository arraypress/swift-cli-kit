//
//  OutFile.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  One file name given to a run that writes several files.
//
//  `caption clip x.mp4 --every 30s -o short.mp4` wrote every clip to
//  short.mp4, each over the last, and exited 0 with one file left. diagram,
//  thumb and caption render each refused it in their own words; the rule
//  lives here once. `OutFolder` is the other half: a folder option given a
//  file name.
//

import Foundation

/// The check for a file-name option when a run writes more than one file.
///
/// A name ending in a file extension (see ``OutFolder/fileExtensions``) that
/// is not an existing folder names ONE file. Given several results it is
/// refused with exit 2 and a message asking for a folder, before anything is
/// written. One result, or a folder, passes.
public enum OutFile {

    /// Whether `path` names a file rather than a folder: it ends in a file
    /// extension and no folder by that name exists.
    ///
    /// Pure: whether the path is an existing folder is passed in.
    public static func namesAFile(
        _ path: String,
        isFolder: Bool,
        fileExtensions: Set<String> = OutFolder.fileExtensions
    ) -> Bool {
        let ext = ((path as NSString).lastPathComponent as NSString).pathExtension.lowercased()
        return !isFolder && fileExtensions.contains(ext)
    }

    /// Why `path` cannot take `results` files, or `nil` when it can.
    ///
    /// - Parameters:
    ///   - path: What was typed for the file option.
    ///   - results: How many files the run will write (a lower bound is fine:
    ///     anything over one is refused).
    ///   - isFolder: Whether a folder already exists at `path`.
    ///   - option: The option's spelling, for the message (`-o`).
    ///   - folderOption: The option that takes a folder, when it is not
    ///     `option` itself (`--out`); `nil` when `option` takes a folder too.
    ///   - fileExtensions: The extensions that make a name a file name.
    /// - Returns: A message for the caller, saying what to type instead.
    public static func problem(
        _ path: String,
        results: Int,
        isFolder: Bool,
        option: String = "-o",
        folderOption: String? = nil,
        fileExtensions: Set<String> = OutFolder.fileExtensions
    ) -> String? {
        guard results > 1, namesAFile(path, isFolder: isFolder, fileExtensions: fileExtensions) else { return nil }
        let name = (path as NSString).lastPathComponent
        let folder = folderOption ?? option
        let stem = (name as NSString).deletingPathExtension
        return "\(option) \(name) names one file, but this run writes \(results): give \(folder) a folder (\(folder) \(stem)) and each file lands inside it."
    }

    /// Refuses `path` when it names one file and the run writes `results`
    /// files — the call for an `execute()`, once the count is known and
    /// before anything is written. Nothing given, nothing to check.
    ///
    /// - Throws: ``CLIError`` with the usage code (exit 2).
    public static func check(
        _ path: String?,
        results: Int,
        option: String = "-o",
        folderOption: String? = nil,
        fileExtensions: Set<String> = OutFolder.fileExtensions
    ) throws {
        guard let path else { return }
        if let message = problem(path, results: results, isFolder: OutFolder.isFolder(path), option: option,
                                 folderOption: folderOption, fileExtensions: fileExtensions) {
            throw CLIError.usage(message)
        }
    }
}
