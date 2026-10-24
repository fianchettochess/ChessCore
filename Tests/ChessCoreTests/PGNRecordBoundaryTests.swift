import XCTest
@testable import ChessCore

final class PGNRecordBoundaryTests: XCTestCase {
    private func comments(_ game: PGNGame) -> [String] {
        game.moveTokens.compactMap { if case .comment(let text) = $0 { return text }; return nil }
    }

    func testTagLookingBraceProseStaysInTheSameGame() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let moveText = "1.e4 {first" + newline + "[Event \"quoted\"]" + newline + "last} e5 *"
            let direct = PGNParser.tokenize(moveText)
            XCTAssertEqual(PGNParser.flatMoves(from: direct), ["e4", "e5"])
            let games = PGNParser.parse("[Event \"Outer\"]" + newline + moveText)
            XCTAssertEqual(games.count, 1)
            let game = try XCTUnwrap(games.first)
            XCTAssertEqual(game.tags["Event"], "Outer")
            XCTAssertEqual(game.moves, ["e4", "e5"])
            XCTAssertEqual(comments(game), ["first\n[Event \"quoted\"]\nlast"])
        }
    }

    func testStandaloneEngineCommandsInsideBracesAreNotTags() throws {
        let game = try XCTUnwrap(PGNParser.parse("[Event \"Engine\"]\n1.e4 {note\n[%eval 0.30]\nmore} e5 *").first)
        XCTAssertEqual(game.moves, ["e4", "e5"])
        XCTAssertEqual(comments(game), ["note\n[%eval 0.30]\nmore"])
        let loaded = try XCTUnwrap(PGNParser.loadGame(from: game))
        XCTAssertEqual(loaded.rootChildren.first?.engineEval, "0.30")
    }

    func testClosingBraceOnATagLookingLineAllowsTheNextRecord() {
        let text = "[Event \"First\"]\n1.e4 {first\n[prose } ; ignore ]\ne5 *\n[Event \"Second\"]\n1.d4 d5 *"
        let games = PGNParser.parse(text)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.first?.tags["Event"], "First")
        XCTAssertEqual(games.first?.moves, ["e4", "e5"])
        XCTAssertEqual(games.last?.tags["Event"], "Second")
        XCTAssertEqual(games.last?.moves, ["d4", "d5"])
    }

    func testBracesInLineCommentsDoNotHideTheNextRecord() {
        for newline in ["\n", "\r\n", "\r"] {
            let text = "[Event \"First\"]" + newline + "1.e4 ; { is prose" + newline
                + "[Event \"Second\"]" + newline + "1.d4 d5 *"
            let games = PGNParser.parse(text)
            XCTAssertEqual(games.count, 2)
            XCTAssertEqual(games.first?.moves, ["e4"])
            XCTAssertEqual(games.last?.tags["Event"], "Second")
            XCTAssertEqual(games.last?.moves, ["d4", "d5"])
        }
    }

    func testSemicolonsAndOpeningBracesInsideBracesDoNotHideTheNextRecord() {
        let text = "[Event \"First\"]\n1.e4 {keep; an opening { is literal}\n[Event \"Second\"]\n1.d4 d5 *"
        let games = PGNParser.parse(text)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.first?.moves, ["e4"])
        XCTAssertEqual(games.last?.moves, ["d4", "d5"])
    }

    func testEOFInsideABraceCommentDoesNotManufactureARecord() {
        let games = PGNParser.parse("[Event \"Outer\"]\n1.e4 {unfinished\n[Event \"prose\"]")
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.tags["Event"], "Outer")
        XCTAssertEqual(games.first?.moves, ["e4"])
    }

    func testOverflowedCommentCannotManufactureARecordAndFollowingGameSurvives() {
        let text = "[Event \"Large\"]\n1.e4 {begin\n" + String(repeating: "oversized ", count: 10)
            + "\n[Event \"Fake\"]\nclosing} e5 *\n[Event \"Good\"]\n1.d4 d5 *"
        let games = PGNParser.parse(text, maximumMoveTextBytes: 24)
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.tags["Event"], "Good")
        XCTAssertEqual(games.first?.moves, ["d4", "d5"])
    }
}
