//
//  ExpandedPathTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import XCTest
@testable import CLIKit

final class ExpandedPathTests: XCTestCase {

    func testALeadingTildeExpandsToHome() {
        XCTAssertEqual("~/Invoices/out.pdf".expandedPath, NSHomeDirectory() + "/Invoices/out.pdf")
    }

    func testABareTildeExpands() {
        XCTAssertEqual("~".expandedPath, NSHomeDirectory())
    }

    func testOtherPathsPassThroughUntouched() {
        // Absolute and relative paths need nothing; a tilde anywhere but the
        // front is a filename character, not a home reference.
        XCTAssertEqual("/tmp/out.pdf".expandedPath, "/tmp/out.pdf")
        XCTAssertEqual("build/out.pdf".expandedPath, "build/out.pdf")
        XCTAssertEqual("/backups/~archive/out.pdf".expandedPath, "/backups/~archive/out.pdf")
    }
}
