import XCTest
@testable import ChessCore

/// A game that ended off the board — resigned, flagged, agreed — has no
/// `GameState` to say so; its result lives only in the Result tag.
final class PGNResultTerminationTests: XCTestCase {

    private func resignedGame() -> Game? {
        PGNParser.loadGame(from: "1. e4 e5 2. Qh5 Nc6 *")
    }

    func testAResignedGameClosesItsMovetextWithTheTaggedResult() throws {
        let game = try XCTUnwrap(resignedGame())
        var tags = PGNGame.OrderedTags()
        tags["Result"] = "1-0"
        let pgn = PGNExporter.export(game: game, tags: tags)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(pgn.contains("[Result \"1-0\"]"))
        XCTAssertTrue(pgn.hasSuffix("1-0"), "movetext must end with the tag's result, got: \(pgn)")
        XCTAssertFalse(pgn.hasSuffix("*"))
    }

    func testAnUnfinishedGameStillClosesWithAStar() throws {
        let game = try XCTUnwrap(resignedGame())
        var tags = PGNGame.OrderedTags()
        tags["Result"] = "*"
        XCTAssertTrue(PGNExporter.export(game: game, tags: tags)
            .trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("*"))
    }

    func testTheReaderTrustsADecidedTagOverAStarToken() {
        let games = PGNParser.parse("[Result \"0-1\"]\n\n1. e4 e5 *")
        XCTAssertEqual(games.first?.resultText, "0-1")
    }

    func testADecidedTokenStillWins() {
        let games = PGNParser.parse("[Result \"*\"]\n\n1. e4 e5 1/2-1/2")
        XCTAssertEqual(games.first?.resultText, "1/2-1/2")
    }

    func testAnEvalAfterALineBreakIsStillAnEval() {
        let parsed = PGNParser.parseEngineComment("solid;\n+0.34;\nbest Nf3")
        XCTAssertEqual(parsed.eval, "+0.34")
        XCTAssertEqual(parsed.bestMove, "Nf3")
        XCTAssertEqual(parsed.comment, "solid")
    }
}
