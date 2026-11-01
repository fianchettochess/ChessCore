import XCTest
@testable import ChessCore

final class PGNTagLineTests: XCTestCase {
    func testTagNamesRoundTripAndCannotInjectMoves() throws {
        let game = try XCTUnwrap(PGNParser.loadGame(from: "1. e4 e5 *"))
        for name in ["Foo.Bar", "White Elo", "Événement", "日本語", "_Private", "!", "a]b"] {
            var tags = PGNGame.OrderedTags()
            tags[name] = "value"
            let parsed = try XCTUnwrap(PGNParser.parse(PGNExporter.export(game: game, tags: tags)).first)
            XCTAssertEqual(parsed.tags[name], "value", name)
        }
        for name in ["", "Ev\nent", "Event\" \"x\"]\n1. d4 d5\n[Injected", "quo\"te"] {
            var tags = PGNGame.OrderedTags()
            tags[name] = "value"
            let exported = PGNExporter.export(game: game, tags: tags)
            XCTAssertFalse(exported.contains("value"), name)
            let parsed = try XCTUnwrap(PGNParser.parse(exported).first)
            XCTAssertEqual(try XCTUnwrap(PGNParser.loadGame(from: parsed)).mainLine.map(\.notation), ["e4", "e5"], name)
        }
    }

    func testTagLineBreaksCannotInjectMovesAndReplaceStoredLine() throws {
        let game = try XCTUnwrap(PGNParser.loadGame(from: "1. e4 e5 *"))
        var tags = PGNGame.OrderedTags()
        tags["Event"] = "a\r\nb\rc\nd\u{0085}e\u{2028}f\u{2029}g"
        let exported = PGNExporter.export(game: game, tags: tags)
        XCTAssertTrue(exported.hasPrefix("[Event \"a b c d e f g\"]\n"))
        let parsed = try XCTUnwrap(PGNParser.parse(exported).first)
        XCTAssertEqual(parsed.tags["Event"], "a b c d e f g")
        let reloaded = try XCTUnwrap(PGNParser.loadGame(from: parsed))
        XCTAssertEqual(reloaded.mainLine.map(\.notation), ["e4", "e5"])
    }
}
