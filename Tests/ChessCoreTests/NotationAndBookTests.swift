import XCTest
@testable import ChessCore

final class NotationAndBookTests: XCTestCase {

    func testPGNParseScholarsMate() {
        let pgn = """
        [Event "Test"]
        [White "A"]
        [Black "B"]
        [Result "1-0"]

        1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0
        """
        let games = PGNParser.parse(pgn)
        XCTAssertEqual(games.count, 1)
        let game = games[0]
        XCTAssertEqual(game.white, "A")
        XCTAssertEqual(game.result, "1-0")
        XCTAssertEqual(game.moves, ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7#"])
    }

    func testPGNMainLineSnapshotReachesMate() {
        let line = PGNParser.mainLineSnapshot(fromMoveText: "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#")
        XCTAssertEqual(line.moves.count, 7)
        let mate = line.moves.last!
        XCTAssertTrue(MoveGenerator.isInCheck(mate.positionAfter))
        XCTAssertFalse(MoveGenerator.hasAnyLegalMove(for: mate.positionAfter))
    }

    func testSANUCIRoundTrip() {
        let pos = Position.initial()
        // e4 as SAN -> Move -> UCI
        XCTAssertEqual(UCIParser.sanToUCI("e4", in: pos), "e2e4")
        // e2e4 as UCI -> SAN
        XCTAssertEqual(UCIParser.uciToSAN("e2e4", in: pos), "e4")
        let move = PGNParser.parseMove("e4", in: pos)
        XCTAssertEqual(move?.uci, "e2e4")
    }

    func testGameTagCodecRoundTripWithEscapes() {
        var tags = PGNGame.OrderedTags()
        tags["White"] = "Carlsen, Magnus"
        tags["Note"] = #"semis; with = and \ backslash"#  // exercises ; = \ escaping
        let encoded = GameTagCodec.encode(tags)
        let decoded = GameTagCodec.decode(encoded)
        XCTAssertEqual(decoded["White"], "Carlsen, Magnus")
        XCTAssertEqual(decoded["Note"], #"semis; with = and \ backslash"#)
        XCTAssertEqual(GameTagCodec.firstValue(forKey: "White", in: encoded), "Carlsen, Magnus")
    }

    // MARK: - PGN comment sanitization

    /// A user comment containing '}' must not terminate the PGN comment block
    /// early on export — the move that follows the comment must still appear in
    /// the exported text.
    func testPGNCommentWithClosingBraceDoesNotCorruptExport() {
        // Build a two-move game where the first move carries a comment with '}'.
        let game = Game()
        let pos0 = game.position
        guard let e4move = PGNParser.parseMove("e4", in: pos0) else {
            XCTFail("could not parse e4"); return
        }
        game.applyMoveFromPGN(e4move)
        if let e4node = game.currentNode {
            e4node.comment = "theory {engine agrees}"
        }
        guard let e5move = PGNParser.parseMove("e5", in: game.position) else {
            XCTFail("could not parse e5"); return
        }
        game.applyMoveFromPGN(e5move)

        let exported = PGNExporter.moveText(for: game.rootChildren)

        // The '}' in the comment must be replaced with ')' so the comment
        // block is terminated only by the exporter-appended '}'.
        // The comment text "theory {engine agrees}" becomes "theory {engine agrees)".
        XCTAssertTrue(exported.contains("engine agrees)"),
                      "closing brace in comment text should be replaced with ')'; got: \(exported)")
        XCTAssertFalse(exported.contains("agrees}"),
                       "raw '}' after 'agrees' must not appear in the export")
        XCTAssertTrue(exported.contains("e5"),
                      "move after the comment must still be present in the output")
    }

    func testStockfishInfoParsing() {
        let info = UCIOutputParser.parseInfo("info depth 20 score cp 35 multipv 1 pv e2e4 e7e5")
        XCTAssertEqual(info?.depth, 20)
        XCTAssertEqual(info?.score.centipawns, 35)
        XCTAssertEqual(info?.pv, ["e2e4", "e7e5"])
        XCTAssertNil(UCIOutputParser.parseInfo("info depth 20 score cp 35 lowerbound pv e2e4"))
        XCTAssertEqual(UCIOutputParser.parseBestMove("bestmove e2e4 ponder e7e5"), "e2e4")
    }

    // MARK: - FEN round-trip with en-passant target + castling rights

    func testFENRoundTripEnPassantAndCastling() {
        // After 1.e4 d5 2.d4: the en-passant target is d3 (White last played d2-d4).
        let fen = "rnbqkbnr/ppp1pppp/8/3p4/3PP3/8/PPP2PPP/RNBQKBNR b KQkq d3 0 2"
        guard let pos = Position(fen: fen) else {
            XCTFail("FEN failed to parse: \(fen)")
            return
        }

        // En-passant target must be d3.
        XCTAssertEqual(pos.enPassantTarget?.algebraic, "d3",
                       "En-passant target square must survive FEN parse")

        // All four castling rights must be intact.
        XCTAssertTrue(pos.castlingRights.whiteKingside,  "White kingside castling must survive")
        XCTAssertTrue(pos.castlingRights.whiteQueenside, "White queenside castling must survive")
        XCTAssertTrue(pos.castlingRights.blackKingside,  "Black kingside castling must survive")
        XCTAssertTrue(pos.castlingRights.blackQueenside, "Black queenside castling must survive")

        // Round-trip: export to FEN string and re-parse.
        let exported = pos.fen
        guard let pos2 = Position(fen: exported) else {
            XCTFail("Re-exported FEN failed to parse: \(exported)")
            return
        }
        XCTAssertEqual(pos2.enPassantTarget?.algebraic, "d3",
                       "En-passant target must survive FEN→string→FEN round-trip")
        XCTAssertEqual(pos2.castlingRights, pos.castlingRights,
                       "Castling rights must be identical after round-trip")
        XCTAssertEqual(pos2.activeColor, .black,
                       "Active colour must survive FEN round-trip")
    }

    // MARK: - PGN round-trip with variation

    func testPGNRoundTripVariation() {
        // PGN with a variation after move 1: '1.e4 (1.d4 d5) e5 *'
        let pgn = "1. e4 ( 1. d4 d5 ) 1... e5 *"
        let g = Game()
        XCTAssertTrue(g.loadPGN(pgn), "PGN with variation must load successfully")

        // Main line must be e4, e5.
        XCTAssertEqual(g.mainLine.map(\.notation), ["e4", "e5"],
                       "Main line must be e4 e5")

        // Root must have two children: e4 (main) and d4 (variation).
        XCTAssertEqual(g.rootChildren.count, 2,
                       "Root must have two children: e4 (main) and d4 (variation)")
        let d4Node = g.rootChildren.first(where: { $0.notation == "d4" })
        XCTAssertNotNil(d4Node, "Variation 1.d4 must be present in root children")
        XCTAssertEqual(d4Node?.children.first?.notation, "d5",
                       "d4 variation must continue with d5")

        // Export and re-import; variation must survive the round-trip.
        let exported = g.exportPGN()
        let g2 = Game()
        XCTAssertTrue(g2.loadPGN(exported), "Re-imported PGN must load")
        XCTAssertEqual(g2.mainLine.map(\.notation), ["e4", "e5"],
                       "Main line must survive PGN round-trip")
        XCTAssertEqual(g2.rootChildren.count, 2,
                       "Variation count must survive PGN export/import")
    }
}
