//
//  CardEmitterTests.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  --card: a result with a card prints its spec as given; one without exits 2;
//  a list uses its element type's collection card; the flag refuses company.
//

import ArgumentParser
import XCTest

@testable import CLIKit

private struct Reading: Codable, TextRenderable, CardRenderable, Sendable {
    let value: Int
    func renderText() -> String { "\(value)" }
    func cardJSON() throws -> Data { Data(#"{"eyebrow":"one","blocks":[]}"#.utf8) }
}

private struct Plain: Codable, TextRenderable, Sendable {
    let value: Int
    func renderText() -> String { "\(value)" }
}

private struct Device: Codable, TableRenderable, CardCollectionRenderable, Sendable {
    let name: String
    static var tableColumns: [String] { ["NAME"] }
    var tableRow: [String] { [name] }
    func renderText() -> String { name }
    static func cardJSON(forAll values: [Any]) throws -> Data {
        let names = values.compactMap { ($0 as? Device)?.name }
        return Data(#"{"eyebrow":"\#(names.joined(separator: "+"))","blocks":[]}"#.utf8)
    }
}

private struct Options: ParsableArguments {
    @OptionGroup var common: CommonOptions
}

final class CardEmitterTests: XCTestCase {

    private func capturingStdout(_ body: () throws -> Void) rethrows -> String {
        let pipe = Pipe()
        let saved = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        try body()
        fflush(stdout)
        dup2(saved, STDOUT_FILENO)
        close(saved)
        try? pipe.fileHandleForWriting.close()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func testACardPrintsItsSpecWhateverTheFormat() throws {
        for format in [OutputFormat.text, .json, .csv] {
            let output = try capturingStdout { try Emitter(format: format, card: true).emit(Reading(value: 3)) }
            XCTAssertEqual(output, #"{"eyebrow":"one","blocks":[]}"# + "\n", "\(format)")
        }
        let normal = try capturingStdout { try Emitter(format: .text).emit(Reading(value: 3)) }
        XCTAssertEqual(normal, "3\n", "without --card, the result as always")
    }

    func testNoCardIsAUsageError() {
        XCTAssertThrowsError(try Emitter(format: .json, card: true).emit(Plain(value: 1))) { error in
            XCTAssertEqual((error as? CLIError)?.code, .usage)
            XCTAssertEqual((error as? CLIError)?.message, "this command has no card")
        }
        XCTAssertThrowsError(try Emitter(format: .json, card: true).emitAll([Plain(value: 1), Plain(value: 2)]))
        XCTAssertThrowsError(try Emitter(format: .json, card: true).emitAll([Reading(value: 1), Reading(value: 2)]),
                             "several single cards are not one card")
    }

    func testAListUsesItsCollectionCard() throws {
        let tabled = try capturingStdout { try Emitter(format: .text, card: true).emitAll([Device(name: "a"), Device(name: "b")]) }
        XCTAssertEqual(tabled, #"{"eyebrow":"a+b","blocks":[]}"# + "\n", "the table overload honours --card too")
        let one = try capturingStdout { try Emitter(format: .json, card: true).emitAll([Reading(value: 1)]) }
        XCTAssertEqual(one, #"{"eyebrow":"one","blocks":[]}"# + "\n", "a list of one single-card result is that card")
    }

    func testTheFlagRefusesFormatsAndFields() throws {
        XCTAssertNoThrow(try Options.parse(["--card"]))
        XCTAssertThrowsError(try Options.parse(["--card", "--json"]))
        XCTAssertThrowsError(try Options.parse(["--card", "--fields", "a"]))
        XCTAssertTrue(try Options.parse(["--card"]).common.emitter.card, "the emitter carries the flag")
        XCTAssertFalse(try Options.parse([]).common.emitter.card)
    }
}
