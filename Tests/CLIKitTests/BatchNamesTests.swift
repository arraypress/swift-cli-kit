//
//  BatchNamesTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The property under test is the one that was lost twice independently:
//  no two inputs may ever share an output name.
//

import XCTest
@testable import CLIKit

final class BatchNamesTests: XCTestCase {

    private func urls(_ paths: String...) -> [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - The plain case

    func testDistinctBasenamesStayBare() throws {
        let names = try BatchNames.unique(
            for: urls("/work/acme.yaml", "/work/globex.yaml"), suffix: ".pdf"
        )
        XCTAssertEqual(names, ["acme.pdf", "globex.pdf"])
    }

    func testTheSuffixIsAppendedVerbatim() throws {
        let names = try BatchNames.unique(for: urls("/work/acme.yaml"), suffix: "-invoice.pdf")
        XCTAssertEqual(names, ["acme-invoice.pdf"])
    }

    func testEmptyInputYieldsEmptyOutputNotACrash() throws {
        XCTAssertEqual(try BatchNames.unique(for: [], suffix: ".pdf"), [])
    }

    // MARK: - Collisions

    func testDuplicateBasenamesGetTheirParentsPrefixedBothOfThem() throws {
        // Prefixing only the second leaves a bare `acme.pdf` that reads as
        // the real one and a stray — they are peers, so both say where they
        // came from.
        let names = try BatchNames.unique(
            for: urls("/2024/acme.yaml", "/2025/acme.yaml", "/2025/globex.yaml"),
            suffix: ".pdf"
        )
        XCTAssertEqual(names, ["2024-acme.pdf", "2025-acme.pdf", "globex.pdf"])
    }

    func testCaseOnlyDifferencesCountAsCollisions() throws {
        // The outputs land on a filesystem that folds case, where Acme.pdf
        // and acme.pdf are one file whatever the listing shows.
        let names = try BatchNames.unique(
            for: urls("/a/Acme.yaml", "/b/acme.yaml"), suffix: ".pdf"
        )
        XCTAssertEqual(names, ["a-Acme.pdf", "b-acme.pdf"])
    }

    func testSameParentAndBasenameFallsBackToNumbering() throws {
        // The parent prefix cannot tell these apart; two files that share a
        // name must still both survive.
        let names = try BatchNames.unique(
            for: urls("/east/branch/spec.yaml", "/west/branch/spec.yaml"),
            suffix: ".pdf"
        )
        XCTAssertEqual(names, ["branch-spec.pdf", "branch-spec-2.pdf"])
    }

    // MARK: - Refusals

    func testTheSameFileTwiceIsRefused() {
        XCTAssertThrowsError(
            try BatchNames.unique(for: urls("/work/acme.yaml", "/work/acme.yaml"), suffix: ".pdf")
        ) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage)
        }
    }

    func testTheSameFileByAnotherSpellingIsRefused() {
        // `a.yaml` and `./a.yaml` are one file; renaming the duplicate would
        // report a batch of two where there was work for one.
        XCTAssertThrowsError(
            try BatchNames.unique(
                for: urls("/work/acme.yaml", "/work/./acme.yaml"), suffix: ".pdf"
            )
        ) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage)
        }
    }
}
