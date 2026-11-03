import XCTest
@testable import ChessCore

final class PGNOversizedRecordTests: XCTestCase {
    func testCountedParsingReportsDiscardedRecordsSoImportsCanDetectMissingGames() {
        let big = "[Event \"Big\"]\n1.e4 {" + String(repeating: "x", count: 40) + "} e5 *"
        let good = "[Event \"Good\"]\n1.d4 d5 *"
        let cases: [(String, [String], Int, Bool)] = [
            (big + "\n" + good, ["Good"], 1, true),
            (good + "\n" + big, ["Good"], 1, false),
            (big, [], 1, true),
            (big + "\n" + big + "\n" + good + "\n" + big, ["Good"], 3, true),
            (good, ["Good"], 0, false),
            ("", [], 0, false)
        ]
        for (text, events, skipped, firstSkipped) in cases {
            let result = PGNParser.parseCounted(text, maximumMoveTextBytes: 24)
            XCTAssertEqual(result.games.map(\.event), events, text)
            XCTAssertEqual(result.oversizedRecordsSkipped, skipped, text)
            XCTAssertEqual(result.firstRecordSkipped, firstSkipped, text)
            XCTAssertEqual(PGNParser.parse(text, maximumMoveTextBytes: 24).map(\.event), events, text)
        }
    }

    func testStringLoaderRejectsSkippedFirstRecordButKeepsFirstGameWhenLaterRecordIsOversized() throws {
        let big = "[Event \"Big\"]\n1.e4 {" + String(repeating: "x", count: 8 * 1024 * 1024) + "} e5 *"
        let good = "[Event \"Good\"]\n1.d4 d5 *"
        let skippedFirst = PGNParser.parseCounted(big + "\n" + good)
        XCTAssertEqual(skippedFirst.games.map(\.event), ["Good"])
        XCTAssertEqual(skippedFirst.oversizedRecordsSkipped, 1)
        XCTAssertTrue(skippedFirst.firstRecordSkipped)
        XCTAssertNil(PGNParser.loadGame(from: big + "\n" + good))

        let skippedLast = PGNParser.parseCounted(good + "\n" + big)
        XCTAssertEqual(skippedLast.oversizedRecordsSkipped, 1)
        XCTAssertFalse(skippedLast.firstRecordSkipped)
        let game = try XCTUnwrap(PGNParser.loadGame(from: good + "\n" + big))
        XCTAssertEqual(PGNExporter.moveText(for: game.rootChildren).trimmingCharacters(in: .whitespacesAndNewlines), "1. d4 d5")
    }
}
