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

    func testUCIInfoParsing() {
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

    // MARK: - SetUp/FEN start-position round-trip

    func testLoadGameHonorsFENStartPosition() {
        // A K+R vs K endgame start: SAN below is only legal from THIS position,
        // so a loader that ignores the FEN tag cannot parse a single move.
        let fen = "8/8/8/4k3/8/8/4K3/7R w - - 0 1"
        let pgn = """
        [Event "Test"]
        [SetUp "1"]
        [FEN "\(fen)"]
        [Result "*"]

        1. Rh5+ Kd4 2. Kd2 *
        """
        guard let game = PGNParser.loadGame(from: pgn) else {
            XCTFail("FEN-start PGN must load"); return
        }
        XCTAssertEqual(game.startPosition.fen, fen,
                       "startPosition must come from the FEN tag, not .initial()")
        XCTAssertEqual(game.mainLine.map(\.notation), ["Rh5+", "Kd4", "Kd2"],
                       "SAN must parse relative to the FEN start position")
    }

    func testLoadGameRejectsInvalidFENTag() {
        let pgn = "[SetUp \"1\"]\n[FEN \"not a fen\"]\n\n1. e4 *"
        XCTAssertNil(PGNParser.loadGame(from: pgn),
                     "A syntactically invalid FEN tag must fail the load, not silently fall back to the initial position")
    }

    func testLoadGameWithoutFENTagUsesInitialStart() {
        guard let game = PGNParser.loadGame(from: "1. e4 e5 *") else {
            XCTFail("standard PGN must load"); return
        }
        XCTAssertEqual(game.startPosition.fen, Position.initial().fen,
                       "No FEN tag → standard initial start, unchanged behaviour")
        XCTAssertEqual(game.mainLine.map(\.notation), ["e4", "e5"])
    }

    func testFENStartExportImportRoundTrip() {
        // Build a game from a FEN start, play moves, export movetext with the
        // OTB-save tag shape, re-import, and require an identical game. This is
        // the exact round-trip the Square Off/e-board OTB save relies on for
        // "start from an existing position" sessions.
        let fen = "8/8/8/4k3/8/8/4K3/7R w - - 0 1"
        let game = Game()
        XCTAssertTrue(game.loadFEN(fen))
        for san in ["Rh5+", "Kd4", "Kd2"] {
            guard let move = PGNParser.parseMove(san, in: game.position) else {
                XCTFail("setup move \(san) must be legal"); return
            }
            game.applyMoveFromPGN(move)
        }

        let moveText = PGNExporter.moveText(for: game.rootChildren)
        let pgn = "[SetUp \"1\"]\n[FEN \"\(fen)\"]\n[Result \"*\"]\n\n\(moveText) *"

        guard let reloaded = PGNParser.loadGame(from: pgn) else {
            XCTFail("exported FEN-start PGN must re-import"); return
        }
        XCTAssertEqual(reloaded.startPosition.fen, fen)
        XCTAssertEqual(reloaded.mainLine.map(\.notation),
                       game.mainLine.map(\.notation),
                       "Moves must survive the FEN-start export/import round-trip")
        XCTAssertEqual(reloaded.mainLine.last?.positionAfter.fen,
                       game.mainLine.last?.positionAfter.fen,
                       "Final position must match after round-trip")
    }

    // MARK: - Spoken labels (shared accessibility phrasing)

    func testPieceSpokenNames() {
        XCTAssertEqual(PieceType.knight.displayName, "knight")
        XCTAssertEqual(Piece(type: .knight, color: .white).descriptiveName, "White knight")
        XCTAssertEqual(Piece(type: .queen, color: .black).descriptiveName, "Black queen")
    }

    func testMoveNodeSpokenLabelBlackPrefixAndAnchoring() {
        // From a mid-game FEN where Black is to move on move 34, the spoken label
        // must use the "..." Black prefix AND the anchored full-move number.
        let fen = "8/8/8/4k3/8/8/4K3/7R b - - 0 34"
        let game = Game()
        XCTAssertTrue(game.loadFEN(fen))
        guard let move = PGNParser.parseMove("Kd5", in: game.position) else {
            XCTFail("Kd5 must be legal"); return
        }
        game.applyMoveFromPGN(move)
        let node = game.mainLine.last!
        XCTAssertEqual(node.spokenLabel(isCurrent: false), "34... Kd5")
        XCTAssertEqual(node.spokenLabel(isCurrent: true), "34... Kd5, current")
    }

    func testMoveNodeSpokenLabelWhiteAndAnnotation() {
        let game = Game()
        guard let e4 = PGNParser.parseMove("e4", in: game.position) else {
            XCTFail("e4 must be legal"); return
        }
        game.applyMoveFromPGN(e4)
        let node = game.mainLine.last!
        XCTAssertEqual(node.spokenLabel(isCurrent: false), "1. e4")
        node.annotation = MoveAnnotation(rawValue: "?!")
        if node.annotation != nil {
            XCTAssertEqual(node.spokenLabel(isCurrent: false), "1. e4, ?!")
        }
    }
}
