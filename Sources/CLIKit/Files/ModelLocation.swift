//
//  ModelLocation.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Where a downloaded model lives: the path named for this run, then an
//  environment variable, then the copy installed in Application Support —
//  the order a per-run choice should beat a per-shell one should beat the
//  default. Nine tools had written this themselves (aud, crate, cutout,
//  embed, img, pix, stems, tune, upscale) before it moved here; a tool that
//  borrows another's model (redub uses stems') names that tool's folder.
//
//  A location with a `source` fetches itself: ``obtain`` downloads a missing
//  model into Application Support on first use, the way Whisper's weights
//  arrive, so a fresh Mac never stops at a two-step manual install. Set
//  NO_MODEL_DOWNLOAD=1 to get the old refusal, with `download` as the hint.
//

import Foundation

/// One downloadable model and the rules for finding and installing it.
public struct ModelLocation: Sendable, Equatable {
    /// The tool the error envelope names.
    public let service: String
    /// The folder under Application Support the model is installed in —
    /// the owning tool's name, which is not always the caller's.
    public let folder: String
    /// The file or bundle names the model may carry, tried in order.
    public let names: [String]
    /// The environment variable that can point at it, if any.
    public let environmentKey: String?
    /// How to get it, for the error that says it is missing.
    public let download: String
    /// Where it can be fetched from automatically, if anywhere.
    public let source: ModelSource?

    /// - Parameters:
    ///   - service: The tool reporting the error.
    ///   - folder: The Application Support folder; defaults to `service`.
    ///   - names: The asset names, tried in order.
    ///   - environmentKey: An environment variable that can point at it.
    ///   - download: How to get it, as the missing-model hint.
    ///   - source: Where ``obtain`` fetches it from when it is missing.
    public init(service: String, folder: String? = nil, names: [String],
                environmentKey: String? = nil, download: String, source: ModelSource? = nil) {
        self.service = service
        self.folder = folder ?? service
        self.names = names
        self.environmentKey = environmentKey
        self.download = download
        self.source = source
    }

    /// This model's folder in the user's Application Support.
    public var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true)
    }

    /// The model to use: the one named, the environment's, or the installed one.
    ///
    /// - Parameters:
    ///   - explicit: A path given for this run, `~` allowed.
    ///   - environment: The environment to read; the process's by default.
    ///   - supportFolder: Where installed models are; ``supportFolder`` by default.
    /// - Returns: The first candidate that exists.
    /// - Throws: ``CLIError`` (not found) naming every place looked, with
    ///   ``download`` as the hint.
    public func resolve(explicit: String?,
                        environment: [String: String] = ProcessInfo.processInfo.environment,
                        supportFolder: URL? = nil) throws -> URL {
        var candidates: [URL] = []
        if let explicit { candidates.append(URL(fileURLWithPath: explicit.expandedPath)) }
        if let environmentKey, let value = environment[environmentKey], !value.isEmpty {
            candidates.append(URL(fileURLWithPath: value.expandedPath))
        }
        let folder = supportFolder ?? self.supportFolder
        candidates += names.map { folder.appendingPathComponent($0) }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw CLIError.notFound("No model found (looked at \(candidates.map(\.path).joined(separator: ", ")))",
                                service: service, hint: download)
    }

    /// The model to use, fetched into Application Support first if it is
    /// nowhere to be found and this location has a ``source``.
    ///
    /// A path named for the run is never replaced by a download: a wrong
    /// `--model` is reported, not quietly papered over.
    ///
    /// - Parameters:
    ///   - explicit: A path given for this run, `~` allowed.
    ///   - quiet: Whether to keep the download's progress off stderr.
    ///   - environment: The environment to read; the process's by default.
    ///   - supportFolder: Where installed models are; ``supportFolder`` by default.
    /// - Returns: The model.
    /// - Throws: ``CLIError`` — not found as ``resolve(explicit:environment:supportFolder:)``
    ///   throws it when there is no source or downloads are off; upstream when
    ///   the download fails.
    public func obtain(explicit: String?, quiet: Bool = false,
                       environment: [String: String] = ProcessInfo.processInfo.environment,
                       supportFolder: URL? = nil) async throws -> URL {
        do {
            return try resolve(explicit: explicit, environment: environment, supportFolder: supportFolder)
        } catch {
            guard explicit == nil, let source, ModelDownloader.isAllowed(environment: environment) else { throw error }
            let folder = supportFolder ?? self.supportFolder
            let reporter = DownloadReporter(service: service, quiet: quiet)
            try await ModelDownloader.download(source, into: folder, service: service) { line, fraction in
                reporter.report(line, fraction)
            }
            reporter.finish()
            return try resolve(explicit: nil, environment: [:], supportFolder: folder)
        }
    }

    /// Copies a downloaded model into Application Support, replacing any there.
    ///
    /// - Parameters:
    ///   - path: The downloaded file or bundle; its name must be one of ``names``.
    ///   - supportFolder: Where to install; ``supportFolder`` by default.
    /// - Returns: Where it was installed.
    /// - Throws: ``CLIError`` when it is missing or is not this model.
    @discardableResult
    public func install(_ path: String, into supportFolder: URL? = nil) throws -> URL {
        let source = URL(fileURLWithPath: path.expandedPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CLIError.notFound("No model at \(source.path)", service: service)
        }
        guard names.contains(source.lastPathComponent) else {
            throw CLIError.usage("The model is \(names.joined(separator: " or ")); \(source.lastPathComponent) is not it")
        }
        let folder = supportFolder ?? self.supportFolder
        _ = try Files.ensureDirectory(folder)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw CLIError.upstream("Could not install \(source.lastPathComponent): \(error.localizedDescription)",
                                    service: service)
        }
        return destination
    }

    /// A file's or a bundle's size on disk, in bytes.
    public static func size(of url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
