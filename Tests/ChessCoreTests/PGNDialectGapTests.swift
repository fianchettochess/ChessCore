import XCTest
@testable import ChessCore

final class PGNDialectGapTests: XCTestCase {
    func testHalfPointResultIsNotCountedAsAMoveAndDrawIsRetained() throws {
        for text in ["1. e4 e5 ½-½", "[Result \"½-½\"]\n1. e4 e5 *"] {
            let game = try XCTUnwrap(PGNParser.parse(text).first)
            XCTAssertEqual(game.moves, ["e4", "e5"], text)
            XCTAssertEqual(game.moveCount, 1, text)
            XCTAssertEqual(game.resultText, "½-½", text)
        }
        XCTAssertEqual(PGNParser.flatMoves(from: PGNParser.tokenize("1. e4 e5 ½-½")), ["e4", "e5"])
        let game = try XCTUnwrap(PGNParser.loadGame(from: "1. e4 e5 *"))
        var tags = PGNGame.OrderedTags()
        tags["Result"] = "½-½"
        XCTAssertEqual(PGNExporter.terminationToken(for: game, tags: tags), "*")
    }

    func testHalfPointInVariationRemainsAMoveTokenSoLegacyReplayDoesNotChange() throws {
        let game = try XCTUnwrap(PGNParser.parse("1. e4 e5 (1... c5 ½-½ 2. Nf3) 2. Nf3 *").first)
        XCTAssertTrue(game.moveTokens.contains { if case .move("½-½") = $0 { return true }; return false })
    }

    func testMultipleTagsKeepEscapedValuesSoImportsDoNotLoseMetadata() throws {
        let text = "[Event \"A ] \\\"quoted\\\"\"][White \"Alice\"] [Black \"Bob\"]\n1. e4 e5 *"
        let game = try XCTUnwrap(PGNParser.parse(text).first)
        XCTAssertEqual(game.tags["Event"], "A ] \"quoted\"")
        XCTAssertEqual(game.tags["White"], "Alice")
        XCTAssertEqual(game.tags["Black"], "Bob")
        XCTAssertEqual(game.moves, ["e4", "e5"])
    }

    func testColumnOneEscapeLinesDoNotSplitRecordsOrHideMoves() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let text = ["% leading {", "[Event \"One\"]", "% between tags", "[White \"Alice\"]",
                        "1. e4", "% [Event \"Fake\"] { 0-1", "e5 *"].joined(separator: newline)
            let games = PGNParser.parse(text)
            XCTAssertEqual(games.count, 1, text)
            let game = try XCTUnwrap(games.first)
            XCTAssertEqual(game.tags["White"], "Alice")
            XCTAssertEqual(game.moves, ["e4", "e5"])
            XCTAssertEqual(game.result, "*")
        }
        let game = try XCTUnwrap(PGNParser.parse("1. e4 {note\n% retained\n} e5 *").first)
        XCTAssertTrue(game.moveTokens.contains { if case .comment(let text) = $0 { return text.contains("% retained") }; return false })
    }
}
