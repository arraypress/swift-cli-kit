//
//  PinnedDownload.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Files fetched from plain URLs and checked against a SHA-256 measured
//  when the URL was chosen — for assets that do not live on Hugging Face
//  (a font from the google/fonts repository at a pinned commit). Like a
//  model download, nothing lands where it is looked for until every file
//  has arrived and checked out, and a cut-off file continues where it
//  stopped. design's open fonts are the first user.
//

import CryptoKit
import Foundation

/// One file at a fixed URL, with the digest it must have.
public struct PinnedFile: Sendable, Equatable {
    /// Where it is fetched from — a URL that names a fixed version.
    public let url: URL
    /// The file name it is installed under.
    public let name: String
    /// Its SHA-256, lowercase hex.
    public let sha256: String

    public init(url: URL, name: String, sha256: String) {
        self.url = url
        self.name = name
        self.sha256 = sha256.lowercased()
    }
}

/// Fetches a set of pinned files into a folder, all or nothing.
public enum PinnedDownload {

    /// The installed copies of `files` in `folder`, when every one is there
    /// and checks out; `nil` otherwise.
    public static func installed(_ files: [PinnedFile], in folder: URL) -> [URL]? {
        var found: [URL] = []
        for file in files {
            let url = folder.appendingPathComponent(file.name)
            guard FileManager.default.fileExists(atPath: url.path),
                  (try? ModelDownloader.digest(of: url, using: SHA256(), prefix: nil)) == file.sha256 else { return nil }
            found.append(url)
        }
        return found
    }

    /// Fetches `files` into `folder` (each under its own name), or returns
    /// them when they are already there and check out.
    ///
    /// - Parameters:
    ///   - files: What to fetch.
    ///   - folder: Where they are installed.
    ///   - label: What they are, for the announcement (`Playfair Display, OFL-1.1`).
    ///   - service: The tool, for errors.
    ///   - quiet: Whether to keep progress off stderr.
    ///   - environment: `NO_MODEL_DOWNLOAD=1` refuses the fetch.
    /// - Returns: The installed files, in the order given.
    /// - Throws: ``CLIError`` — not found when downloads are off, upstream
    ///   when a file cannot be fetched or does not match its digest.
    @discardableResult
    public static func obtain(_ files: [PinnedFile], into folder: URL, label: String, service: String, quiet: Bool = false,
                              environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> [URL] {
        if let found = installed(files, in: folder) { return found }
        guard ModelDownloader.isAllowed(environment: environment) else {
            throw CLIError.notFound("\(label) is not installed and downloads are off (\(ModelDownloader.disableKey))",
                                    service: service, hint: "unset \(ModelDownloader.disableKey) to fetch it")
        }
        let reporter = DownloadReporter(service: service, quiet: quiet, done: "\(label) installed")
        defer { reporter.finish() }
        reporter.report("fetching \(label) (\(files.count) file\(files.count == 1 ? "" : "s"))", nil)
        _ = try Files.ensureDirectory(folder)
        let key = files.map { "\($0.url.absoluteString)#\($0.sha256)" }.joined(separator: ",")
        let tag = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let staging = folder.appendingPathComponent(".download-\(tag)", isDirectory: true)
        _ = try Files.ensureDirectory(staging)
        for (index, file) in files.enumerated() {
            let destination = staging.appendingPathComponent(file.name)
            if (try? ModelDownloader.digest(of: destination, using: SHA256(), prefix: nil)) == file.sha256 { continue }
            reporter.report(file.name, Double(index) / Double(files.count))
            try await ModelDownloader.fetch(file.url, to: destination, service: service) { _ in }
            guard try ModelDownloader.digest(of: destination, using: SHA256(), prefix: nil) == file.sha256 else {
                try? FileManager.default.removeItem(at: destination)
                throw CLIError.upstream("\(file.name) arrived but does not match its pinned SHA-256", service: service)
            }
        }
        var installed: [URL] = []
        for file in files {
            let final = folder.appendingPathComponent(file.name)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: staging.appendingPathComponent(file.name), to: final)
            installed.append(final)
        }
        try? FileManager.default.removeItem(at: staging)
        return installed
    }
}
