import XCTest
@testable import ChessCore

/// A game that ended off the board — resigned, flagged, agreed — has no
/// `GameState` to say so; its result lives only in the Result tag.
final class PGNResultTerminationTests: XCTestCase {
    func testRulesResultWinsContradictoryTagInBothHeaderAndMovetext() throws {
        let game = try XCTUnwrap(PGNParser.loadGame(from: "1. f3 e5 2. g4 Qh4# 0-1"))
        for tagged in ["1-0", "1/2-1/2", "*", "invalid"] {
            var tags = PGNGame.OrderedTags()
            tags["Result"] = tagged
            let pgn = PGNExporter.export(game: game, tags: tags)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(pgn.contains("[Result \"0-1\"]"))
            XCTAssertTrue(pgn.hasSuffix("0-1"))
            XCTAssertEqual(PGNParser.parse(pgn).first?.resultText, "0-1")
        }
    }

    func testSuppliedSparseTagsDoNotFabricateResultMetadata() throws {
        let game = try XCTUnwrap(resignedGame())
        var tags = PGNGame.OrderedTags()
        tags["Event"] = "Test"
        let pgn = PGNExporter.export(game: game, tags: tags)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(pgn.contains("[Result "))
        XCTAssertTrue(pgn.hasSuffix("*"))
    }

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

    // A best move wrapped onto its OWN line is still the best move. The
    // exporter wraps movetext at any space, inside braces too, so
    // `{+0.34; best Qh5}` can come out as `{+0.34; best` and `Qh5}` on two
    // lines. Both full-file and direct movetext readers preserve those
    // line breaks, and trimming the ENDS of each `;`
    // part cannot reach a break in the middle of one. Reported by the
    // Fianchetto Windows face, 2026-09-22.
    func testABestMoveWrappedOntoItsOwnLineIsStillTheBestMove() {
        for separator in ["\n", "\r\n", "\t", "  "] {
            let parsed = PGNParser.parseEngineComment("+0.34; best\(separator)Qh5")
            XCTAssertEqual(parsed.bestMove, "Qh5", "separator \(separator.debugDescription)")
            XCTAssertEqual(parsed.eval, "+0.34")
            XCTAssertNil(parsed.comment)
        }
    }

    func testAWordThatOnlyStartsWithBestIsStillProse() {
        let parsed = PGNParser.parseEngineComment("bestiary; best")
        XCTAssertNil(parsed.bestMove)
        XCTAssertEqual(parsed.comment, "bestiary; best")
    }

    func testAWrappedBestMoveSurvivesTheTokenizer() throws {
        let comments = PGNParser.tokenize("1. e4 {+0.34; best\nd4} e5").compactMap { token -> String? in
            if case .comment(let text) = token { return text }
            return nil
        }
        XCTAssertEqual(comments.count, 1)
        let parsed = PGNParser.parseEngineComment(try XCTUnwrap(comments.first))
        XCTAssertEqual(parsed.bestMove, "d4")
    }
}
