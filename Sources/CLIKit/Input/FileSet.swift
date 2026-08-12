//
//  FileSet.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turning what somebody typed into the list of files they meant.
///
/// Every tool that works in bulk needs the same thing — take some paths, some
/// of which are folders, and end up with a list of files — and every tool that
/// writes it itself gets the same two details wrong. This is here so they get
/// written once.
public enum FileSet {

    /// Every file named by `paths`, in a stable order.
    ///
    /// A path that is a file is taken as given, whatever it is called: the
    /// caller named it outright and second-guessing that helps nobody. A path
    /// that is a folder is walked, keeping files whose extension is in
    /// `extensions`.
    ///
    /// - Parameters:
    ///   - paths: Files, folders, or a mixture.
    ///   - extensions: Lowercase, without the dot. An empty string matches a
    ///     file with no extension at all, which is how a list called `emails`
    ///     gets picked up.
    ///   - recursive: Whether to descend into sub-folders.
    /// - Throws: ``CLIError`` when a path does not exist. A typo that silently
    ///   matches nothing is worse than a refusal, because the run reports
    ///   success over an empty set.
    public static func gather(
        _ paths: [String],
        matching extensions: Set<String>,
        recursive: Bool = false
    ) throws -> [URL] {
        var found: [URL] = []
        let manager = FileManager.default

        for path in paths {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw CLIError.usage("No such file or folder: \(path)")
            }
            let url = URL(fileURLWithPath: path)

            guard isDirectory.boolValue else {
                found.append(url)
                continue
            }

            let options: FileManager.DirectoryEnumerationOptions =
                recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            guard let walker = manager.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey], options: options
            ) else { continue }

            for case let candidate as URL in walker
            where extensions.contains(candidate.pathExtension.lowercased()) {
                // A folder has no extension either. Where "" is accepted so
                // that extensionless files are found, every sub-folder would
                // otherwise be counted as one.
                let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                found.append(candidate)
            }
        }

        // Sorted, because a folder arrives in whatever order the filesystem
        // felt like, and two runs over the same folder should report the same
        // thing in the same order.
        return found.sorted { $0.path < $1.path }
    }
}

// MARK: - Lists of values

/// Reading a file that holds one value per line.
///
/// The ordinary bulk case is a column of a spreadsheet — addresses, part
/// numbers, measurements — saved out and handed to a tool.
public enum ValueList {

    /// The extensions a list of values usually arrives under.
    public static let extensions: Set<String> = ["txt", "csv", "tsv", "list", "lst", ""]

    /// One value, and where it came from.
    public struct Value: Sendable, Equatable {

        public let text: String

        /// `contacts.csv:4213`, or nothing for a value given as an argument.
        ///
        /// A run over an export reports thousands of these, and any one of
        /// them is only actionable with the line beside it.
        public let source: String?

        public init(text: String, source: String? = nil) {
            self.text = text
            self.source = source
        }
    }

    /// The values in a file, one per line.
    ///
    /// Blank lines and `#` comments are skipped but still counted, so the
    /// number reported is the number in the file. Splitting them away makes
    /// every reference after the first gap wrong, which is worse than giving
    /// no line at all.
    ///
    /// Surrounding quotes are stripped, because that is how a spreadsheet
    /// writes a one-column export.
    public static func read(_ url: URL) throws -> [Value] {
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CLIError.usage("Could not read \(url.lastPathComponent) as text")
        }

        let name = url.lastPathComponent
        return contents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in
                let text = line
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
                return Value(text: text, source: "\(name):\(index + 1)")
            }
    }

    /// Everything in every file named, folders walked.
    public static func read(
        paths: [String], recursive: Bool = false
    ) throws -> [Value] {
        try FileSet.gather(paths, matching: extensions, recursive: recursive)
            .flatMap(read)
    }
}
