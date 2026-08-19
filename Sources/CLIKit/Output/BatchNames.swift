//
//  BatchNames.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Output filenames for a batch, derived from the inputs' own names.
//
//  Every tool that renders many inputs needs the same thing — `acme.yaml`
//  becomes `acme.pdf` — and every tool that writes it itself rediscovers the
//  same fault: two inputs called `acme.yaml` in different folders, and the
//  second output silently overwrites the first. A batch that reports success
//  over half its work is the failure mode this family tries hardest to avoid,
//  so the naming is written once, here.
//

import Foundation

/// Derives one output filename per input file.
public enum BatchNames {

    /// A unique output name for each input, in the same order.
    ///
    /// Names are the input's basename with the extension swapped for
    /// `suffix`: `/work/acme.yaml` with `".pdf"` becomes `acme.pdf`. When two
    /// inputs share a basename, *both* are prefixed with their parent
    /// directory's name — `2024-acme.pdf` beside `2025-acme.pdf` — so neither
    /// output masquerades as the plain name the other run produced. Inputs
    /// that also share a parent name fall back to numbering, because two
    /// files that cannot be told apart by name must still both survive.
    ///
    /// Collisions are judged case-insensitively: the outputs land on a
    /// filesystem that folds case, where `Acme.pdf` and `acme.pdf` are one
    /// file whatever the listing shows.
    ///
    /// - Parameters:
    ///   - inputs: The files being rendered, in output order.
    ///   - suffix: Appended verbatim to each derived stem — include the dot,
    ///     `".pdf"`, or a qualified form like `"-invoice.pdf"`.
    /// - Returns: One filename per input, positionally matched.
    /// - Throws: ``CLIError`` with code `usage` when two inputs are the same
    ///   file — `a.yaml` and `./a.yaml` — because the duplicate is a mistake
    ///   in the invocation, not a naming problem to be papered over.
    public static func unique(for inputs: [URL], suffix: String) throws -> [String] {
        // The same file twice is refused, not renamed: the caller asked for
        // one document twice, and producing `acme.pdf` and `acme-2.pdf` with
        // identical contents reports a batch of two where there was work for
        // one.
        var resolved: Set<String> = []
        for url in inputs {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard resolved.insert(path).inserted else {
                throw CLIError.usage(
                    "\(url.path) is given twice",
                    hint: "each input produces one output; drop the duplicate"
                )
            }
        }

        let stems = inputs.map { $0.deletingPathExtension().lastPathComponent }

        var occurrences: [String: Int] = [:]
        for stem in stems { occurrences[stem.lowercased(), default: 0] += 1 }

        var names: [String] = []
        var taken: Set<String> = []

        for (index, url) in inputs.enumerated() {
            var stem = stems[index]

            // Prefix every member of a collision, not just the latecomers:
            // a bare `acme.pdf` beside `2025-acme.pdf` reads as the real one
            // and the stray, when they are peers.
            if occurrences[stem.lowercased(), default: 0] > 1 {
                let parent = url.deletingLastPathComponent().lastPathComponent
                if !parent.isEmpty, parent != "/" {
                    stem = "\(parent)-\(stem)"
                }
            }

            var candidate = stem
            var counter = 2
            while taken.contains(candidate.lowercased()) {
                candidate = "\(stem)-\(counter)"
                counter += 1
            }
            taken.insert(candidate.lowercased())
            names.append(candidate + suffix)
        }
        return names
    }
}
