import XCTest
@testable import ChessCore

final class PGNFENExportTests: XCTestCase {
    func testStandardStartsOmitSetupTags() throws {
        let games = [Game(), try XCTUnwrap(PGNParser.loadGame(from: "[FEN \"\(Position.initial().fen)\"]\n\n1. e4 *"))]
        for game in games {
            let text = PGNExporter.export(game: game)
            XCTAssertFalse(text.contains("[SetUp "))
            XCTAssertFalse(text.contains("[FEN "))
        }
    }

    func testInvalidTagNamesAreSkipped() {
        var tags = PGNGame.OrderedTags()
        for key in ["Ev\nent", "]\n\n1. d4", "_invalid"] { tags[key] = "injected" }
        tags["Valid_Name"] = "kept"
        let text = PGNExporter.export(game: Game(), tags: tags)
        XCTAssertFalse(text.contains("injected"))
        XCTAssertTrue(text.contains("[Valid_Name \"kept\"]"))
    }

    func testDefaultExportPreservesFENStartAndMovesWhenReimported() throws {
        let input = "[SetUp \"1\"]\n[FEN \"8/8/8/8/8/8/4K3/7k w - - 0 1\"]\n\n1. Kf3 *"
        let original = try XCTUnwrap(PGNParser.loadGame(from: input))
        let exported = PGNExporter.export(game: original)
        XCTAssertTrue(exported.contains("[SetUp \"1\"]"))
        XCTAssertTrue(exported.contains("[FEN \"8/8/8/8/8/8/4K3/7k w - - 0 1\"]"))
        let reimported = try XCTUnwrap(PGNParser.loadGame(from: exported))
        XCTAssertEqual(reimported.startPosition, original.startPosition)
        XCTAssertEqual(reimported.mainLine.map(\.notation), ["Kf3"])
    }
}
