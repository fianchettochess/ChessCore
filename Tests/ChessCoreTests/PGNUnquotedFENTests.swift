import XCTest
@testable import ChessCore

final class PGNUnquotedFENTests: XCTestCase {
    func testValidUnquotedFENPreventsReplayingMovesOnTheWrongBoard() throws {
        let cases: [(String, String, [String])] = [
            ("8/P7/8/8/8/8/8/k1K5 w - - 0 1", "1. a8=Q", ["a8=Q#"]),
            ("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", "1... e5 2. Nf3", ["e5", "Nf3"])
        ]
        for (fen, moves, notation) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse("[FEN \(fen)]\n\n\(moves)").first)
            XCTAssertEqual(parsed.tags.orderedKeys, ["FEN"])
            XCTAssertEqual(parsed.tags["FEN"], fen)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(report.game.startPosition, Position(fen: fen))
            XCTAssertEqual(report.game.mainLine.map(\.notation), notation)
            XCTAssertTrue(report.canReplaceStoredText)
        }
    }

    func testInvalidFENAndOtherUnquotedTagsCannotChangeImportedIdentity() throws {
        for header in ["[FEN not-a-fen]", "[White Alice]"] {
            let parsed = try XCTUnwrap(PGNParser.parse("\(header)\n\n1. e4").first)
            XCTAssertTrue(parsed.tags.isEmpty, header)
            XCTAssertEqual(try XCTUnwrap(PGNParser.loadGame(from: parsed)).mainLine.map(\.notation), ["e4"])
        }
    }

    func testUnquotedFENCannotOverwriteExistingOrQuotedTags() throws {
        let original = "8/P7/8/8/8/8/8/k1K5 w - - 0 1"
        let other = Position.initial().fen
        for headers in ["[FEN \"\(original)\"]\n[FEN \(other)]", "[White \"Alice\"] [FEN \(other)]"] {
            let parsed = try XCTUnwrap(PGNParser.parse("\(headers)\n\n*").first)
            if headers.hasPrefix("[FEN \"") {
                XCTAssertEqual(parsed.tags["FEN"], original)
            } else {
                XCTAssertNil(parsed.tags["FEN"])
                XCTAssertEqual(parsed.tags["White"], "Alice")
            }
        }
    }
}
