import XCTest
@testable import ChessCore

final class PGNLineCommentTests: XCTestCase {
    private let mainline = ["e4", "e5", "Nf3", "Nc6"]
    private func comments(_ tokens: [PGNToken]) -> [String] {
        tokens.compactMap { if case .comment(let text) = $0 { return text }; return nil }
    }

    func testTokenizerEndsLineCommentsAtEachNewlineDialect() {
        for newline in ["\n", "\r\n", "\r"] {
            let tokens = PGNParser.tokenize("1.e4; comment ♞ 😀" + newline + "e5 2.Nf3 Nc6 *")
            XCTAssertEqual(PGNParser.flatMoves(from: tokens), mainline)
            XCTAssertEqual(comments(tokens), [" comment ♞ 😀"])
        }
    }

    func testCommentDelimitersAndResultsAreProseUntilTheLineEnds() throws {
        let text = "1.e4; (not a variation) {not braces} $7 0-1\ne5 2.Nf3 Nc6 *"
        let game = try XCTUnwrap(PGNParser.parse("[Result \"*\"]\n\n" + text).first)
        XCTAssertEqual(game.moves, mainline)
        XCTAssertEqual(game.resultText, "*")
        XCTAssertEqual(comments(game.moveTokens), [" (not a variation) {not braces} $7 0-1"])
    }

    func testFullParserKeepsLineBoundariesAcrossRecords() {
        let first = "[Event \"First\"]\n1.e4 ; line one\ne5 2.Nf3 Nc6 *"
        let second = "[Event \"Second\"]\n1.d4; line two\nd5 *"
        let games = PGNParser.parse(first + "\n" + second)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.first?.moves, mainline)
        XCTAssertEqual(games.last?.moves, ["d4", "d5"])
        XCTAssertEqual(games.first.map { comments($0.moveTokens) }, [" line one"])
        XCTAssertEqual(games.last.map { comments($0.moveTokens) }, [" line two"])
    }

    func testEOFCommentsCannotOverrideTheGameResult() throws {
        let game = try XCTUnwrap(PGNParser.parse("[Result \"*\"]\n1.e4 e5 * ; ignore 0-1").first)
        XCTAssertEqual(game.moves, ["e4", "e5"])
        XCTAssertEqual(game.resultText, "*")
        XCTAssertEqual(comments(game.moveTokens), [" ignore 0-1"])
        XCTAssertTrue(PGNParser.flatMoves(from: PGNParser.tokenize("; only a comment")).isEmpty)
    }

    func testLineCommentsInsideVariationsDoNotLeakIntoTheMainline() {
        let tokens = PGNParser.tokenize("1.e4 e5 (1...c5 ; ignore ) { ( $9\n2.Nf3 d6) 2.Nf3 Nc6 *")
        XCTAssertEqual(PGNParser.flatMoves(from: tokens), mainline)
        XCTAssertEqual(comments(tokens), [" ignore ) { ( $9"])
    }

    func testBraceCommentsKeepTheirSemicolonsAndLineBreaks() throws {
        let game = try XCTUnwrap(PGNParser.parse("[Event \"Brace control\"]\n1.e4 {keep; best d4\nand more} e5 *").first)
        XCTAssertEqual(game.moves, ["e4", "e5"])
        XCTAssertEqual(comments(game.moveTokens), ["keep; best d4\nand more"])
    }

    func testResultsInBraceCommentsAndVariationsCannotOverrideTheMainline() throws {
        for suffix in ["{ignore 0-1}", "(1...c5 0-1)", "; ignore 0-1"] {
            let game = try XCTUnwrap(PGNParser.parse("1.e4 e5 1-0 " + suffix).first)
            XCTAssertEqual(game.resultText, "1-0")
            XCTAssertEqual(game.moves, ["e4", "e5"])
        }
    }

    func testFullParserRetainsBlankLinesAndCommentWhitespace() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let game = try XCTUnwrap(PGNParser.parse("1.e4; prose  " + newline + "e5 *").first)
            XCTAssertEqual(game.moves, ["e4", "e5"])
            XCTAssertEqual(comments(game.moveTokens), [" prose  "])
        }
        let game = try XCTUnwrap(PGNParser.parse("1.e4 {first\n\n  last  } e5 *").first)
        XCTAssertEqual(comments(game.moveTokens), ["first\n\n  last  "])
    }

    func testLongClosingBraceCommentDoesNotWrapIntoMoves() throws {
        let prose = "literal } " + String(repeating: "comment words ", count: 15) + "end"
        let parsed = try XCTUnwrap(PGNParser.parse("1.e4 ;" + prose + "\ne5 2.Nf3 Nc6 *").first)
        let loaded = try XCTUnwrap(PGNParser.loadGame(from: parsed))
        let exported = PGNExporter.export(game: loaded)
        let reparsed = try XCTUnwrap(PGNParser.parse(exported).first)
        XCTAssertEqual(reparsed.moves, mainline)
        XCTAssertEqual(comments(reparsed.moveTokens), [prose])
    }

    func testExportedCommentsWithClosingBracesKeepFollowingMoves() throws {
        let document = "[Event \"Roundtrip\"]\n1.e4 ; keep } and { as prose\ne5 2.Nf3 Nc6 *"
        let parsed = try XCTUnwrap(PGNParser.parse(document).first)
        let stored = PGNExporter.tokenText(from: parsed)
        let reparsed = PGNParser.tokenize(stored)
        XCTAssertEqual(PGNParser.flatMoves(from: reparsed), mainline)
        XCTAssertEqual(comments(reparsed), [" keep } and { as prose"])
        let loaded = try XCTUnwrap(PGNParser.loadGame(from: parsed))
        let exported = PGNExporter.export(game: loaded)
        let exportedGame = try XCTUnwrap(PGNParser.parse(exported).first)
        XCTAssertEqual(exportedGame.moves, mainline)
        XCTAssertEqual(comments(exportedGame.moveTokens).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, ["keep } and { as prose"])
    }
}
