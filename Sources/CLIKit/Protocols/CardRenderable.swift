//
//  CardRenderable.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  A result that can be drawn as a card. With `--card` a tool prints its
//  answer as a card spec — the JSON the `card` tool (and CardKit) draws — so
//  an agent pipes `tool … --card | card -o x.png` instead of re-typing the
//  numbers into a card by hand, where they get copied wrong.
//
//  CLIKit knows nothing about cards beyond "some JSON": the tool builds the
//  spec with CardKit and hands over the bytes, so this module stays free of
//  SwiftUI and every tool that has no card pays nothing.
//

import Foundation

/// A single result that has a card.
public protocol CardRenderable {
    /// This result as a card spec for `card`: CardKit's `Card`, encoded.
    func cardJSON() throws -> Data
}

/// A list of results that together make one card (a summary table, a set of
/// devices). Implement it on the element type; ``Emitter/emitAll(_:)`` calls it
/// with the whole list when `--card` is set.
public protocol CardCollectionRenderable {
    /// The whole list as one card spec. `values` holds elements of the
    /// conforming type.
    static func cardJSON(forAll values: [Any]) throws -> Data
}
