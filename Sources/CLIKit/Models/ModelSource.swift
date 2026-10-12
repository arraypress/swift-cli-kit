//
//  ModelSource.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Where a model can be fetched from when it is not installed: a public
//  Hugging Face repository and the top-level folders in it that make up the
//  model. Every model the fleet ships is laid out that way — one folder per
//  asset (`stems-htdemucs-float32.aimodel/`, `LaMa.mlpackage/`), plus the odd
//  support folder beside it — so naming the folders is enough to fetch it.
//

import Foundation

/// A Hugging Face repository a model can be fetched from: public, or gated
/// behind a licence the person must accept first (``isGated``).
public struct ModelSource: Sendable, Equatable {
    /// `owner/name`, as in the repository's URL.
    public let repository: String
    /// The top-level files or folders to fetch, each installed under its
    /// own name.
    public let paths: [String]
    /// The licence, named in the line that announces the download.
    public let licence: String?
    /// The branch, tag or commit to fetch.
    public let revision: String
    /// Whether the repository asks people to accept a licence before
    /// downloading. A gated source is fetched with the person's own Hugging
    /// Face token (``HuggingFaceToken``); without one, or without access, the
    /// download stops with exit 3 and the steps to get it.
    public let isGated: Bool

    /// - Parameters:
    ///   - repository: `owner/name` on huggingface.co.
    ///   - paths: The top-level files or folders that make up the model.
    ///   - licence: The licence, for the announcement.
    ///   - revision: The branch, tag or commit; `main` by default.
    ///   - gated: Whether the repository needs an accepted licence and a token.
    public init(repository: String, paths: [String], licence: String? = nil, revision: String = "main",
                gated: Bool = false) {
        self.repository = repository
        self.paths = paths
        self.licence = licence
        self.revision = revision
        self.isGated = gated
    }
}
