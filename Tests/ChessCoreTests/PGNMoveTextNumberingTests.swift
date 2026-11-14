import XCTest
@testable import ChessCore

final class PGNMoveTextNumberingTests: XCTestCase {
    /// Gates explicit adoption of FEN numbering. Changing the default offset
    /// would change FianchettoKit's stored movetext hashes and duplicate rows;
    /// a parity error in the opt-in path would label Black's move as White's.
    func testCorrectFENNumberingRequiresOptInSoLegacyMovetextBytesAndStoredHashesStayStable() throws {
        // The first two legacy literals also appear in the captured 0.17.1
        // compatibility fixtures. Extra starts and branches gate offset/parity.
        let cases: [(String, String, String)] = [
            ("[FEN \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 23\"]\n23... e5 24. Nf3 *",
             "1. e5 Nf3", "23... e5 24. Nf3"),
            ("1. e4 e5 2. Nf3 Nc6 *",
             "1. e4 e5 2. Nf3 Nc6", "1. e4 e5 2. Nf3 Nc6"),
            ("[FEN \"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 23\"]\n23. e4 e5 *",
             "1. e4 e5", "23. e4 e5"),
            ("[FEN \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1\"]\n1... e5 2. Nf3 *",
             "1. e5 Nf3", "1... e5 2. Nf3"),
            ("[Event \"Numbered branches\"]\n[FEN \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 23\"]\n23... e5 {reply} (23... c5 {Sicilian}) 24. Nf3 Nc6 (24... Nf6) 25. Bb5 *",
             "1. e5 {reply} ( 1. c5 {Sicilian} ) Nf3 2. Nc6 ( 2. Nf6 ) Bb5",
             "23... e5 {reply} ( 23... c5 {Sicilian} ) 24. Nf3 Nc6 ( 24... Nf6 ) 25. Bb5")
        ]
        for (input, legacyGolden, correctedGolden) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(input).first)
            let game = try XCTUnwrap(PGNParser.loadGame(from: parsed))
            let before = try GameTreeSnapshot(capturing: game)
            let legacy = PGNExporter.moveText(for: game.rootChildren)
            let corrected = PGNExporter.moveText(for: game.rootChildren, numberingFrom: game.startPosition)
            XCTAssertEqual(Array(legacy.utf8), Array(legacyGolden.utf8), input)
            XCTAssertEqual(corrected, correctedGolden, input)
            XCTAssertEqual(try GameTreeSnapshot(capturing: game), before, input)

            // Keep identical tag text around each movetext so a numbering
            // migration must preserve moves, variations, comments and tags.
            let header = parsed.tags.isEmpty ? "" : PGNExporter.export(game: game, tags: parsed.tags)
                .components(separatedBy: "\n\n")[0]
            var reparsedTrees: [GameTreeSnapshot] = []
            for text in [legacy, corrected] {
                let reparsed = try XCTUnwrap(PGNParser.parse(header + "\n\n" + text + " *").first)
                XCTAssertEqual(reparsed.tags, parsed.tags, input)
                let replay = try PGNParser.loadGame(from: reparsed, maximumTreeNodes: 100)
                let tree = try GameTreeSnapshot(capturing: replay)
                XCTAssertEqual(tree, before, input)
                reparsedTrees.append(tree)
            }
            XCTAssertEqual(reparsedTrees.first, reparsedTrees.last, input)
        }
    }
}
