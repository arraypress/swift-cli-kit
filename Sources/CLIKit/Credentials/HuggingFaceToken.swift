//
//  HuggingFaceToken.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The one Hugging Face credential the fleet shares, for gated models — a
//  repository that asks people to accept a licence before downloading
//  (FLUX.2 Klein 9B, SAM 3). Never a command-line argument: it comes from the
//  environment, from `hf auth login`'s own file, or from the fleet's
//  credential store, in that order.
//

import Foundation

/// Finds the Hugging Face token gated downloads send.
public enum HuggingFaceToken {

    /// The fleet service the token is stored under.
    public static let service = ServiceSpec(
        id: "huggingface",
        displayName: "Hugging Face",
        toolName: "hf",
        credentials: [CredentialSpec(key: "token", label: "access token",
                                     envNames: ["HF_TOKEN", "HUGGING_FACE_HUB_TOKEN"])],
        signupURL: "https://huggingface.co/settings/tokens"
    )

    /// Where a token was found.
    public enum Source: String, Sendable, Equatable {
        case environment
        case huggingFaceCLI
        case store
    }

    /// The token and where it came from, or `nil` when there is none.
    ///
    /// - Parameters:
    ///   - environment: Checked first: `HF_TOKEN`, then `HUGGING_FACE_HUB_TOKEN`.
    ///   - home: Whose `~/.cache/huggingface/token` (`hf auth login`) to read
    ///     next; `HF_HOME` moves it, as the Hugging Face tools do.
    ///   - store: The fleet's credential store, read last.
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser,
                               store: CredentialStore = FileCredentialStore()) -> (token: String, source: Source)? {
        for name in service.credentials[0].envNames {
            if let value = clean(environment[name]) { return (value, .environment) }
        }
        let folder = environment["HF_HOME"].flatMap(clean).map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".cache/huggingface")
        if let text = try? String(contentsOf: folder.appendingPathComponent("token"), encoding: .utf8),
           let value = clean(text) {
            return (value, .huggingFaceCLI)
        }
        if let value = clean((try? store.read(service: service.id, key: "token")) ?? nil) {
            return (value, .store)
        }
        return nil
    }

    /// The steps that let someone fetch a gated repository: the error text
    /// IS the onboarding.
    public static func onboarding(for repository: String) -> String {
        "open https://huggingface.co/\(repository), sign in and accept its licence, then run "
            + "`hf auth login` (or export HF_TOKEN) with a token from \(service.signupURL ?? "huggingface.co")"
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
