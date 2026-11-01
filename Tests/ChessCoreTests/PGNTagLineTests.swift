import XCTest
@testable import ChessCore

final class PGNTagLineTests: XCTestCase {
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
