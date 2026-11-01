import XCTest
@testable import ChessCore

final class PGNImputationTests: XCTestCase {
    func testUniqueContinuationReportsImputationSoStoredMovesAreNotSilentlyReplaced() throws {
        let parsed = try XCTUnwrap(PGNParser.parse("1. d4 Zz8 2. Nf3 e4 *").first)
        let report = try XCTUnwrap(PGNParser.loadGameWithImputation(from: parsed))
        XCTAssertEqual(report.imputedMoves.map(\.originalToken), ["Zz8"])
        XCTAssertEqual(report.imputedMoves.map(\.notation), ["e5"])
        XCTAssertEqual(report.imputedMoves.map(\.plyIndex), [1])
        XCTAssertEqual(report.game.mainLine.map(\.notation), ["d4", "e5", "Nf3", "e4"])
        XCTAssertTrue(report.droppedMoveTokens.isEmpty)
        XCTAssertFalse(report.mainLineDiffersFromSnapshot)
    }
    func testAmbiguousContinuationDoesNotInventMoveAndReportsLoss() throws {
        let parsed = try XCTUnwrap(PGNParser.parse("1. e4 Zz9 2. Nf3 *").first)
        let report = try XCTUnwrap(PGNParser.loadGameWithImputation(from: parsed))
        XCTAssertTrue(report.imputedMoves.isEmpty)
        XCTAssertEqual(report.droppedMoveTokens, ["Zz9", "Nf3"])
        XCTAssertEqual(report.game.mainLine.map(\.notation), ["e4"])
    }
    func testRefusesUnreliableRepairs() throws {
        let cases = [
            "1. b3 e5 xx 2. d4 *", "1. b3 e5 a9 2. d4 *",
            "1. d4 Zz8 2. Nf3 *", "1. d4 Zz8 *",
            "1. d4 resigns 2. Nf3 e4 *", "1. d4 -- 2. Nf3 e4 *",
            "1. d4 Zz9 (1... e5 2. dxe5) 2. Nf3 e4 *",
            "(1. d4 d5) 1. e4 f5 2. Qh5+ Zz9 *",
            "1. d4 Zz8 (1... e5 2. dxe5) 2. Nf3 e4 *",
            // Skipping the token already replays the tail, so it is stray even
            // though exactly one inserted move would also fit.
            "1. h4 f5 Zz8 2. h5 c5 *"
        ]
        for text in cases {
            let input = try XCTUnwrap(PGNParser.parse(text).first)
            let report = try XCTUnwrap(PGNParser.loadGameWithImputation(from: input))
            XCTAssertTrue(report.imputedMoves.isEmpty, text)
            XCTAssertEqual(report.game.mainLine.map(\.move), PGNParser.loadGame(from: input)?.mainLine.map(\.move), text)
        }
        var flat = PGNGame()
        flat.moves = ["d4", "Zz9", "7", "Nf3", "e4"]
        XCTAssertTrue(try XCTUnwrap(PGNParser.loadGameWithImputation(from: flat)).imputedMoves.isEmpty)
    }

    func testStrayPlausibleTokenAndImputedPlyIndex() throws {
        let input = try XCTUnwrap(PGNParser.parse("1. b3 e5 Zz8 2. d4 exd4 *").first)
        XCTAssertTrue(try XCTUnwrap(PGNParser.loadGameWithImputation(from: input)).imputedMoves.isEmpty)
        let repaired = try XCTUnwrap(PGNParser.loadGameWithImputation(from: XCTUnwrap(PGNParser.parse("1. d4 Zz8 2. Nf3 e4 *").first)))
        XCTAssertFalse(repaired.canReplaceStoredText)
        for move in repaired.imputedMoves {
            XCTAssertTrue(repaired.game.mainLine.indices.contains(move.plyIndex))
            XCTAssertEqual(repaired.game.mainLine[move.plyIndex].notation, move.notation)
        }
    }
    func testForcedMoveStillRequiresTwoFollowingPlies() throws {
        for tail in ["", "Rh8+"] {
            var input = PGNGame()
            input.tags["FEN"] = "7k/8/5K2/8/8/8/8/7R b - - 0 1"
            input.moves = ["Zz8"] + (tail.isEmpty ? [] : [tail])
            let report = try XCTUnwrap(PGNParser.loadGameWithImputation(from: input))
            XCTAssertTrue(report.imputedMoves.isEmpty, tail)
        }
    }

    func testOversizedMainLineIsRefused() {
        var input = PGNGame()
        input.moves = Array(repeating: "Zz8", count: PGNParser.maximumMoveTreeNodes + 1)
        XCTAssertNil(PGNParser.loadGameWithImputation(from: input))
    }
}
