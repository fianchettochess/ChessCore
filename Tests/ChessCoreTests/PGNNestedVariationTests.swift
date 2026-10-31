import XCTest
@testable import ChessCore

/// Saved library games persist only their PGN movetext, so a nested analysis
/// line has to survive export and re-import in its original place.
final class PGNNestedVariationTests: XCTestCase {

    private func tree(_ movetext: String) throws -> GameTreeSnapshot {
        let game = try XCTUnwrap(PGNParser.loadGame(from: movetext))
        return try GameTreeSnapshot(capturing: game)
    }

    func testNestedVariationsRoundTripAtDepthsTwoAndThree() throws {
        let cases = [
            "1. e4 e5 2. Nf3 ( 2. Bc4 Nf6 ( 2... Bc5 3. c3 ) 3. d3 ) 2... Nc6 *",
            "1. e4 e5 2. Nf3 ( 2. Bc4 Nf6 ( 2... Bc5 3. c3 ( 3. Nf3 d6 ) 3... d6 ) ( 2... Nc6 3. Nf3 ) 3. d3 ) 2... Nc6 3. Bb5 *",
            "1. e4 e5 2. Nf3 ( 2. Bc4 $1 { develops } Nf6 ( 2... Bc5 { solid } 3. c3 ) 3. d3 ) 2... Nc6 *",
            // Nd4 is legal for either side, and must keep its standard reading.
            "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3. Nd4 ) 3... e6 ) 1... e5 *",
            // Written after e6 instead of e3, Nd4 would replay as a black move.
            "1. e4 ( 1. Nf3 Nc6 2. Nc3 e6 3. e3 ( 3. Nd4 ) ) 1... e5 *",
        ]
        for movetext in cases {
            let original = try XCTUnwrap(PGNParser.loadGame(from: movetext))
            let firstExport = original.exportPGN()
            let reloaded = try XCTUnwrap(PGNParser.loadGame(from: firstExport))

            XCTAssertEqual(reloaded.exportPGN(), firstExport, movetext)
            XCTAssertEqual(
                try GameTreeSnapshot(capturing: reloaded),
                try GameTreeSnapshot(capturing: original),
                movetext
            )
        }
    }

    func testOldExporterOrderLoadsAsTheTreeItWasWrittenFrom() throws {
        let intended = "1. e4 e5 2. Nf3 ( 2. Bc4 Nf6 ( 2... Bc5 3. c3 ) ( 2... d6 ) 3. d3 ) 2... Nc6 *"
        // The same tree as stored by exporters that wrote a line's
        // alternatives ahead of the move they replace.
        let stored = "1. e4 e5 2. Nf3 ( 2. Bc4 ( 2... Bc5 3. c3 ) ( 2... d6 ) 2... Nf6 3. d3 ) Nc6"

        XCTAssertEqual(try tree(stored), try tree(intended))
    }

    func testOldExporterOrderIsRecognisedWhenTheFirstMoveIsLegalForBothSides() throws {
        // Both sides can play Nd4 here, so only exd4 shows where the line starts.
        let intended = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 e6 ( 3... Nd4 4. exd4 ) 4. d4 ) 1... e5 *"
        let stored = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4 4. exd4 ) 3... e6 4. d4 ) e5"

        XCTAssertEqual(try tree(stored), try tree(intended))
    }
}
