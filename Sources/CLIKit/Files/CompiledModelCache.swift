//
//  CompiledModelCache.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  Core AI's compiled copies of a model. The first load of an `.aimodel` in
//  a program specialises it for this Mac and keeps the result under
//  ~/Library/Caches/coreai-cache/<OS build>/<program>/<content hash>/ — one
//  copy per program that loads it, out of sight, and as large as the model
//  or larger. Removing a model should remove its copies too; the next load
//  simply compiles again. sfx and imagine each wrote this walk before it
//  moved here; the key is the asset's `main.hash`.
//

import Foundation

/// The compiled copies Core AI keeps of each `.aimodel`.
public enum CompiledModelCache {

    /// The cache's root: `~/Library/Caches/coreai-cache`.
    public static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("coreai-cache")
    }

    /// The content hash Core AI files an asset's compiled copy under: its
    /// `main.hash`, as lower-case hex. `nil` when `asset` is not a Core AI asset.
    public static func contentHash(of asset: URL) -> String? {
        guard let data = try? Data(contentsOf: asset.appendingPathComponent("main.hash")), !data.isEmpty else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// Every `.aimodel` at or under `item` (a model folder may hold several).
    public static func assets(under item: URL) -> [URL] {
        if item.pathExtension == "aimodel" { return [item] }
        var found: [URL] = []
        if let walk = FileManager.default.enumerator(at: item, includingPropertiesForKeys: nil) {
            for case let url as URL in walk where url.pathExtension == "aimodel" {
                found.append(url)
                walk.skipDescendants()
            }
        }
        return found
    }

    /// Every compiled copy of the asset with `hash`, for any program, any OS
    /// build; with `program`, only that program's.
    public static func copies(of hash: String, program: String? = nil, root: URL = CompiledModelCache.root) -> [URL] {
        let manager = FileManager.default
        var found: [URL] = []
        for build in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let programs = program.map { [build.appendingPathComponent($0)] }
                ?? ((try? manager.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? [])
            for folder in programs {
                let entry = folder.appendingPathComponent(hash)
                if manager.fileExists(atPath: entry.path) { found.append(entry) }
            }
        }
        return found
    }

    /// Whether `program` has compiled `asset` already — what decides whether
    /// a run warns that its first load will take a while.
    public static func isCompiled(_ asset: URL, program: String, root: URL = CompiledModelCache.root) -> Bool {
        contentHash(of: asset).map { !copies(of: $0, program: program, root: root).isEmpty } ?? false
    }

    /// Bytes the compiled copies of every asset at or under `item` take, every program's.
    public static func bytes(of item: URL, root: URL = CompiledModelCache.root) -> Int64 {
        assets(under: item).compactMap(contentHash(of:)).reduce(0) { total, hash in
            total + copies(of: hash, root: root).reduce(0) { $0 + ModelLocation.size(of: $1) }
        }
    }

    /// Removes every compiled copy of every asset at or under `item`, every
    /// program's. The model itself is left. Returns the bytes freed.
    @discardableResult
    public static func remove(_ item: URL, root: URL = CompiledModelCache.root) -> Int64 {
        var freed: Int64 = 0
        for hash in assets(under: item).compactMap(contentHash(of:)) {
            for copy in copies(of: hash, root: root) {
                freed += ModelLocation.size(of: copy)
                try? FileManager.default.removeItem(at: copy)
            }
        }
        return freed
    }

    /// Removes `item` and every compiled copy of the assets in it. Returns
    /// the bytes freed, both counted; `0` when there was nothing there.
    @discardableResult
    public static func removeModel(_ item: URL, root: URL = CompiledModelCache.root) -> Int64 {
        guard FileManager.default.fileExists(atPath: item.path) else { return 0 }
        let freed = remove(item, root: root) + ModelLocation.size(of: item)
        try? FileManager.default.removeItem(at: item)
        return freed
    }
}
