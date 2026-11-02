import XCTest
@testable import ChessCore

final class PGNDialectGapTests: XCTestCase {
    func testOddQuotesRecoverLegacyTagsSoMetadataAndIdentitySurvive() throws {
        let cases: [(String, [String: String])] = [
            ("[White \"O\"Neil\"]\n[Black \"B\"]\n\n1. e4 *\n", ["White": "O", "Black": "B"]),
            ("[Event \"a\"b\"]", ["Event": "a"]),
            ("[Result \"1-0\"\"]\n[White \"W\"]", ["Result": "1-0", "White": "W"])
        ]
        for (text, expected) in cases {
            let game = try XCTUnwrap(PGNParser.parse(text).first, text)
            XCTAssertEqual(Set(game.tags.orderedKeys), Set(expected.keys), text)
            for (key, value) in expected { XCTAssertEqual(game.tags[key], value, text) }
        }
    }

    func testHalfPointRemainsMoveTokenSoStoredRowKeysAndResultSurvive() throws {
        let tokens = PGNParser.tokenize("e4 e5 ½-½")
        XCTAssertEqual(tokens.count, 3)
        guard tokens.count == 3, case .move("e4") = tokens[0],
              case .move("e5") = tokens[1], case .move("½-½") = tokens[2] else {
            return XCTFail("Expected three move tokens: e4, e5, ½-½")
        }
        let game = try XCTUnwrap(PGNParser.parse("[Result \"1-0\"]\n\n1. e4 e5 ½-½").first)
        XCTAssertEqual(game.resultText, "1-0")
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
