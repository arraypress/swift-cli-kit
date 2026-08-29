//
//  XDGTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class XDGTests: XCTestCase {

    private let fallback = URL(fileURLWithPath: "/Users/someone/.config", isDirectory: true)

    func testAnAbsoluteValueIsTaken() {
        XCTAssertEqual(XDG.directory("/srv/config", or: fallback).path, "/srv/config")
    }

    func testARelativeValueIsIgnoredAsTheSpecificationSays() {
        XCTAssertEqual(XDG.directory("config", or: fallback), fallback)
    }

    func testAnEmptyOrAbsentValueFallsBack() {
        XCTAssertEqual(XDG.directory("", or: fallback), fallback)
        XCTAssertEqual(XDG.directory(nil, or: fallback), fallback)
    }

    func testTheHomesEndWhereTheFamilyExpects() {
        // Whatever the environment says, the fallbacks are the conventional
        // dot-directories under the user's home, and the two are different.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let config = XDG.configHome.path, cache = XDG.cacheHome.path
        XCTAssertTrue(config.hasPrefix("/"), config)
        XCTAssertTrue(cache.hasPrefix("/"), cache)
        XCTAssertNotEqual(config, cache)
        if ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] == nil {
            XCTAssertEqual(config, home + "/.config")
        }
        if ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] == nil {
            XCTAssertEqual(cache, home + "/.cache")
        }
    }
}
