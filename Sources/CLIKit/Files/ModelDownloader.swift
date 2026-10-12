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
//  It does leave what already arrived (0.13.2): the staging folder is named
//  for the model rather than for the run, files that check out are kept, and
//  a cut-off file continues from where it stopped with an HTTP Range — a
//  dropped 14 GB download used to start again from nothing.
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
        let size = fileSize(file)
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
        let token = try token(for: source, service: service)
        let entries = try await listing(of: source, service: service, token: token)
        let wanted = files(in: entries, under: source.paths)
        let missing = source.paths.filter { path in !wanted.contains { $0.path == path || $0.path.hasPrefix(path + "/") } }
        guard missing.isEmpty else {
            throw CLIError.upstream("\(source.repository) has no \(missing.joined(separator: ", "))", service: service)
        }
        let total = wanted.reduce(0) { $0 + $1.bytes }
        progress("fetching \(source.paths.joined(separator: " + ")) (\(total.fileSizeText)"
                 + (source.licence.map { ", \($0)" } ?? "") + ") from huggingface.co/\(source.repository)", nil)

        _ = try Files.ensureDirectory(folder)
        removeAbandonedStaging(in: folder)
        // Named for the model, and kept when a run fails, so the next run
        // picks up what already arrived.
        let staging = folder.appendingPathComponent(stagingName(for: source), isDirectory: true)
        var done: Int64 = 0
        for entry in wanted {
            let destination = staging.appendingPathComponent(entry.path)
            _ = try Files.ensureDirectory(destination.deletingLastPathComponent())
            let have = fileSize(destination)
            if have == entry.bytes, (try? verify(destination, against: entry)) == true {
                done += entry.bytes
                continue
            }
            if have > entry.bytes { try? FileManager.default.removeItem(at: destination) }
            if have > 0, have < entry.bytes {
                progress("resuming \(entry.path) at \(have.fileSizeText) of \(entry.bytes.fileSizeText)", nil)
            }
            let base = done
            try await fetch(fileURL(source, entry.path), to: destination, service: service,
                            token: token, repository: source.repository) { received in
                progress(entry.path, total > 0 ? Double(base + received) / Double(total) : nil)
            }
            guard try verify(destination, against: entry) else {
                // A bad file must not be resumed from: the next run starts it clean.
                try? FileManager.default.removeItem(at: destination)
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
        try? FileManager.default.removeItem(at: staging)
        return installed
    }

    /// The staging folder for one model: the same name every run, so a
    /// later run finds what an interrupted one left.
    static func stagingName(for source: ModelSource) -> String {
        let key = "\(source.repository)@\(source.revision):\(source.paths.sorted().joined(separator: ","))"
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return ".download-\(hash)"
    }

    /// Whether a folder is a staging folder from before 0.13.2, named for a
    /// run (`.download-<UUID>`) — nothing can ever resume from it.
    static func isAbandonedStaging(_ name: String) -> Bool {
        guard name.hasPrefix(".download-") else { return false }
        return UUID(uuidString: String(name.dropFirst(".download-".count))) != nil
    }

    /// Removes the pre-0.13.2 staging folders a killed run left behind.
    static func removeAbandonedStaging(in folder: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where isAbandonedStaging(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// A file's size, 0 when it is not there — read from the file system
    /// every time. `URL.resourceValues` caches on the URL: a resumed file
    /// that grew from 16 KB to 224 MB still read as 16 KB, and a perfect
    /// download failed its size check.
    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// What to do with the bytes already on disk, given the server's answer
    /// to a request that asked for the rest.
    enum Continuation: Equatable {
        /// 206: the server sent the rest — append.
        case append
        /// 200: the server ignored the Range and sent everything — start over.
        case restart
        /// 416: nothing left to send — the file is already whole (the
        /// checksum decides).
        case complete
        /// Anything else.
        case fail(Int)
    }

    static func continuation(have: Int64, status: Int) -> Continuation {
        switch status {
        case 206 where have > 0: .append
        case 200: .restart
        case 416 where have > 0: .complete
        default: .fail(status)
        }
    }

    /// The token a gated source is fetched with; `nil` for a public one.
    ///
    /// - Throws: ``CLIError`` (auth, exit 3) when the source is gated and no
    ///   token is set — the message is how to get one.
    static func token(for source: ModelSource, service: String,
                      environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String? {
        guard source.isGated else { return nil }
        guard let found = HuggingFaceToken.resolve(environment: environment) else {
            throw CLIError.authRequired("\(source.repository) is gated: it needs a Hugging Face token with access",
                                        service: service, hint: HuggingFaceToken.onboarding(for: source.repository))
        }
        return found.token
    }

    /// A refusal of a gated repository as the exit-3 error that says how to
    /// get in: 401 is a token Hugging Face does not accept, 403 an account
    /// that has not accepted the licence (or is still waiting for approval).
    static func accessError(status: Int, repository: String, service: String) -> CLIError? {
        switch status {
        case 401:
            return CLIError.authRequired("huggingface.co did not accept the token for \(repository)",
                                         service: service, hint: HuggingFaceToken.onboarding(for: repository))
        case 403:
            return CLIError.authRequired("No access to \(repository) yet — its licence has not been accepted on this account",
                                         service: service, hint: HuggingFaceToken.onboarding(for: repository))
        default:
            return nil
        }
    }

    /// A request carrying the token, when there is one.
    static func request(_ url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// The repository's files.
    static func listing(of source: ModelSource, service: String, token: String? = nil) async throws -> [Entry] {
        let url = URL(string: "https://huggingface.co/api/models/\(source.repository)/tree/\(source.revision)?recursive=true")!
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request(url, token: token)) } catch {
            throw CLIError.upstream("Could not reach huggingface.co: \(error.localizedDescription)", service: service)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if source.isGated, let refusal = accessError(status: status, repository: source.repository, service: service) {
            throw refusal
        }
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

    /// One file, to a path, continuing from whatever part of it is already
    /// there, and reporting the bytes on disk as they grow so a
    /// multi-gigabyte weight file does not read as a hang. Cancelling the
    /// calling task stops the transfer; what arrived is kept for next time.
    static func fetch(_ url: URL, to destination: URL, service: String,
                      token: String? = nil, repository: String? = nil,
                      received: @escaping @Sendable (Int64) -> Void) async throws {
        let have = fileSize(destination)
        // Hugging Face checks the token, then redirects to its CDN with a
        // signed URL that needs none — measured on a gated repo (sam3).
        var request = request(url, token: token)
        if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CLIError.upstream("Fetching \(url.lastPathComponent) failed: \(error.localizedDescription)",
                                    service: service)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if token != nil, let repository, let refusal = accessError(status: status, repository: repository, service: service) {
            throw refusal
        }
        let start: Int64
        switch continuation(have: have, status: status) {
        case .append: start = have
        case .restart: start = 0
        case .complete: return
        case .fail(let code):
            throw CLIError.upstream("Fetching \(url.lastPathComponent) failed: HTTP \(code)", service: service)
        }
        if start == 0 || !FileManager.default.fileExists(atPath: destination.path) {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw CLIError.upstream("Could not write \(destination.path)", service: service)
            }
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        if start == 0 { try handle.truncate(atOffset: 0) } else { try handle.seekToEnd() }

        var written: Int64 = start
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        received(written)
        // Every byte kept is a valid prefix of the file, so whatever arrived
        // before a failure is written down for the next run to continue from.
        func flush() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
            received(written)
        }
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 20 {
                    try flush()
                    try Task.checkCancellation()
                }
            }
            try flush()
        } catch is CancellationError {
            try? flush()
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            try? flush()
            throw CancellationError()
        } catch {
            try? flush()
            throw CLIError.upstream("Fetching \(url.lastPathComponent) stopped at \(written.fileSizeText): "
                                    + "\(error.localizedDescription) — run again to continue from there",
                                    service: service)
        }
    }
}
