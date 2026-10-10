//
//  ModelDownloader.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Fetches a ModelSource from Hugging Face into a folder, checked rather than
//  assumed: the file list comes from the repository's API, every large file
//  is checked against the SHA-256 the API publishes for it and every small
//  one against its git blob hash, and nothing lands where a model is looked
//  for until all of it has arrived and checked out — a download cut off
//  halfway leaves no half-model to be loaded and fail strangely later.
//  cutout had written the file walk for itself; it moved here when every
//  model-using tool needed it.
//

import CryptoKit
import Foundation

/// Downloads models from public Hugging Face repositories.
public enum ModelDownloader {

    /// One file in a repository, as the tree API lists it.
    struct Entry: Decodable, Equatable {
        struct LFS: Decodable, Equatable { let oid: String; let size: Int64 }
        let type: String
        let path: String
        let oid: String?
        let size: Int64?
        let lfs: LFS?

        /// The bytes the file should have.
        var bytes: Int64 { lfs?.size ?? size ?? 0 }
    }

    /// The environment variable that turns automatic downloads off.
    public static let disableKey = "NO_MODEL_DOWNLOAD"

    /// Whether automatic downloads are allowed in this environment.
    public static func isAllowed(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let value = environment[disableKey]?.lowercased(), !value.isEmpty else { return true }
        return !["1", "true", "yes"].contains(value)
    }

    /// The files of a listing that belong to the paths asked for.
    ///
    /// - Parameters:
    ///   - entries: The repository's files.
    ///   - paths: Top-level files or folders.
    /// - Returns: The files under them, in listing order.
    static func files(in entries: [Entry], under paths: [String]) -> [Entry] {
        entries.filter { entry in
            entry.type == "file" && paths.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") }
        }
    }

    /// Whether a downloaded file is the one the listing describes: SHA-256
    /// for a large (LFS) file, the git blob hash for a small one.
    static func verify(_ file: URL, against entry: Entry) throws -> Bool {
        let size = Int64((try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
        guard size == entry.bytes else { return false }
        if let lfs = entry.lfs {
            return try digest(of: file, using: SHA256(), prefix: nil) == lfs.oid
        }
        guard let oid = entry.oid else { return true }
        return try digest(of: file, using: Insecure.SHA1(), prefix: Data("blob \(size)\0".utf8)) == oid
    }

    /// A hex digest of a file, read in chunks so a 3 GB weight file is not
    /// held in memory.
    static func digest<H: HashFunction>(of file: URL, using hasher: H, prefix: Data?) throws -> String {
        var hasher = hasher
        if let prefix { hasher.update(data: prefix) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Fetches a model's files into a folder.
    ///
    /// - Parameters:
    ///   - source: Where from.
    ///   - folder: Where each of the source's paths is installed, under its own name.
    ///   - service: The tool, for errors.
    ///   - progress: Called with a line to show; a nil `fraction` is an announcement.
    /// - Returns: The installed paths.
    /// - Throws: ``CLIError`` (upstream) when the listing, a file or a check fails.
    @discardableResult
    public static func download(_ source: ModelSource, into folder: URL, service: String,
                                progress: @escaping @Sendable (String, Double?) -> Void) async throws -> [URL] {
        let entries = try await listing(of: source, service: service)
        let wanted = files(in: entries, under: source.paths)
        let missing = source.paths.filter { path in !wanted.contains { $0.path == path || $0.path.hasPrefix(path + "/") } }
        guard missing.isEmpty else {
            throw CLIError.upstream("\(source.repository) has no \(missing.joined(separator: ", "))", service: service)
        }
        let total = wanted.reduce(0) { $0 + $1.bytes }
        progress("fetching \(source.paths.joined(separator: " + ")) (\(total.fileSizeText)"
                 + (source.licence.map { ", \($0)" } ?? "") + ") from huggingface.co/\(source.repository)", nil)

        _ = try Files.ensureDirectory(folder)
        let staging = folder.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var done: Int64 = 0
        for entry in wanted {
            let destination = staging.appendingPathComponent(entry.path)
            _ = try Files.ensureDirectory(destination.deletingLastPathComponent())
            let base = done
            try await fetch(fileURL(source, entry.path), to: destination, service: service) { received in
                progress(entry.path, total > 0 ? Double(base + received) / Double(total) : nil)
            }
            guard try verify(destination, against: entry) else {
                throw CLIError.upstream("\(entry.path) arrived but does not match its published checksum", service: service)
            }
            done += entry.bytes
        }

        var installed: [URL] = []
        for path in source.paths {
            let final = folder.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: staging.appendingPathComponent(path), to: final)
            installed.append(final)
        }
        return installed
    }

    /// The repository's files.
    static func listing(of source: ModelSource, service: String) async throws -> [Entry] {
        let url = URL(string: "https://huggingface.co/api/models/\(source.repository)/tree/\(source.revision)?recursive=true")!
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(from: url) } catch {
            throw CLIError.upstream("Could not reach huggingface.co: \(error.localizedDescription)", service: service)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw CLIError.upstream("huggingface.co answered \(status) for \(source.repository)", service: service)
        }
        do { return try JSONDecoder().decode([Entry].self, from: data) } catch {
            throw CLIError.upstream("huggingface.co did not return the file list for \(source.repository)", service: service)
        }
    }

    /// Where one file downloads from.
    static func fileURL(_ source: ModelSource, _ path: String) -> URL {
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "https://huggingface.co/\(source.repository)/resolve/\(source.revision)/\(escaped)")!
    }

    /// One file, to a path, reporting the bytes received every half second
    /// so a multi-gigabyte weight file does not read as a hang.
    static func fetch(_ url: URL, to destination: URL, service: String,
                      received: @escaping @Sendable (Int64) -> Void) async throws {
        let box = TaskBox()
        let watcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let task = box.task { received(task.countOfBytesReceived) }
            }
        }
        defer { watcher.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { temporary, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let temporary, error == nil, status == 200 else {
                    let why = error?.localizedDescription ?? "HTTP \(status)"
                    continuation.resume(throwing: CLIError.upstream("Fetching \(url.lastPathComponent) failed: \(why)",
                                                                    service: service))
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            box.task = task
            task.resume()
        }
    }

    /// Holds the running task for the progress watcher.
    private final class TaskBox: @unchecked Sendable {
        var task: URLSessionDownloadTask?
    }
}
