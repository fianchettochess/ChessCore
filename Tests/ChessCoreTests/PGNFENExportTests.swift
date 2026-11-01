import XCTest
@testable import ChessCore

final class PGNFENExportTests: XCTestCase {
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
