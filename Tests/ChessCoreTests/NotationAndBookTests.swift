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

    func testPGNParseDropsOverflowedGameWithoutLosingFollowingGame() {
        let oversized = """
        [Event "Oversized"]
        [White "A"]
        [Black "B"]
        [Result "*"]

        1. e4 e5 2. Nf3 Nc6
        3. Bb5 a6 4. Ba4 Nf6
        """
        let valid = """
        [Event "Valid"]
        [White "C"]
        [Black "D"]
        [Result "1-0"]

        1. d4 d5 1-0
        """

        let games = PGNParser.parse(
            oversized + "\n" + valid,
            maximumMoveTextBytes: 24
        )

        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games[0].event, "Valid")
        XCTAssertEqual(games[0].moves, ["d4", "d5"])
    }

    func testPGNParseMovetextWithoutBlankLineAfterTags() {
        // Regression: inTags was only cleared by an empty line, so movetext
        // that directly follows the headers (hand-edited / web-copied PGN)
        // was silently dropped — tags imported with ZERO moves.
        let pgn = """
        [Event "Test"]
        [White "A"]
        [Black "B"]
        [Result "1-0"]
        1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0
        """
        let games = PGNParser.parse(pgn)
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games[0].white, "A")
        XCTAssertEqual(games[0].result, "1-0")
        XCTAssertEqual(games[0].moves, ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7#"])
    }

    func testPGNParseTwoConcatenatedGamesWithoutBlankSeparators() {
        // Regression companion: consecutive no-blank-line games used to merge
        // their tag sections into one PGNGame. They must parse as TWO games,
        // each with its own tags and moves.
        let pgn = """
        [Event "First"]
        [White "A"]
        1. e4 e5 1-0
        [Event "Second"]
        [White "C"]
        1. d4 d5 0-1
        """
        let games = PGNParser.parse(pgn)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games[0].event, "First")
        XCTAssertEqual(games[0].white, "A")
        XCTAssertEqual(games[0].moves, ["e4", "e5"])
        XCTAssertEqual(games[0].result, "1-0")
        XCTAssertEqual(games[1].event, "Second")
        XCTAssertEqual(games[1].white, "C")
        XCTAssertEqual(games[1].moves, ["d4", "d5"])
        XCTAssertEqual(games[1].result, "0-1")
    }

    func testPGNMainLineSnapshotReachesMate() {
        let line = PGNParser.mainLineSnapshot(fromMoveText: "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#")
        XCTAssertEqual(line.moves.count, 7)
        let mate = line.moves.last!
        XCTAssertTrue(MoveGenerator.isInCheck(mate.positionAfter))
        XCTAssertFalse(MoveGenerator.hasAnyLegalMove(for: mate.positionAfter))
    }

    func testParseMainLineSnapshotHonorsFENTag() {
        // Regression: parseMainLineSnapshot pinned Position.initial() even
        // when the game carries a [FEN] tag (which loadGame honors). SANs of
        // FEN-setup games were parsed against the wrong board and silently
        // dropped, yielding an empty/desynced mainline.
        let pgn = """
        [SetUp "1"]
        [FEN "8/8/4k3/8/8/4K3/8/R7 w - - 0 1"]

        1. Ra6+ Kf5 2. Kf3 *
        """
        let games = PGNParser.parse(pgn)
        XCTAssertEqual(games.count, 1)
        let parsed = PGNParser.parseMainLineSnapshot(from: games[0])
        XCTAssertEqual(parsed.startPosition.fen, "8/8/4k3/8/8/4K3/8/R7 w - - 0 1",
                       "snapshot must start from the [FEN] tag position")
        XCTAssertEqual(parsed.moves.map(\.notation), ["Ra6+", "Kf5", "Kf3"],
                       "every SAN must parse relative to the FEN start")
    }

    func testExportEscapesQuoteAndBackslashInTagValues() {
        // Regression: the exporter emitted tag values verbatim, so a quote or
        // backslash produced out-of-spec PGN (§8.1: '\' and '"' must be
        // escaped) whose header string terminates early in conforming
        // readers (SCID, python-chess, Lichess).
        let raw = #"He said "hi" \ once"#
        let game = Game()
        var tags = PGNGame.OrderedTags()
        tags["Event"] = "Escaping"
        tags["White"] = raw

        let exported = PGNExporter.export(game: game, tags: tags)
        XCTAssertTrue(exported.contains(#"[White "He said \"hi\" \\ once"]"#),
                      "tag value must be §8.1-escaped on export, got: \(exported)")

        // Round-trip through our own parser must recover the original value.
        let reparsed = PGNParser.parse(exported)
        XCTAssertEqual(reparsed.count, 1)
        XCTAssertEqual(reparsed[0].white, raw)
    }

    func testTagScannerStopsAtFirstUnescapedQuote() {
        // §8.1: a tag's string token ends at the first UNESCAPED quote.
        // Trailing junk after the close — even junk containing quotes —
        // must not fold into the value. A first/last-quote-pairing scanner
        // gets every one of these wrong.
        let cases: [(line: String, key: String, value: String)] = [
            // Quote after the intended close.
            (#"[White "a" junk "b"]"#, "White", "a"),
            // Value ENDING in an escaped quote, then junk with quotes.
            (#"[Event "say \"hi\"" x "y"]"#, "Event", #"say "hi""#),
            // Value ending in an escaped backslash (the following quote is
            // a real close, not an escape), then junk with quotes.
            (#"[Event "trailing\\" x "y"]"#, "Event", #"trailing\"#),
        ]
        for c in cases {
            let games = PGNParser.parse(c.line + "\n\n*\n")
            XCTAssertEqual(games.count, 1, "case: \(c.line)")
            XCTAssertEqual(games[0].tags[c.key], c.value, "case: \(c.line)")
        }
    }

    func testTagValueExportImportRoundTripsExactly() {
        // Contract pin: §8.1 escaping on export + escape-aware scan on parse
        // must round-trip any value EXACTLY — including quote/backslash at
        // the very end of the value, where naive scanners break.
        let values = [
            #"plain"#,
            #"He said "hi" \ once"#,
            #"ends with quote""#,
            #"ends with backslash\"#,
            #""leading quote"#,
            #"back\slash "and" quotes"#,
            #"bracket ] inside"#,
        ]
        for raw in values {
            var tags = PGNGame.OrderedTags()
            tags["Event"] = "RT"
            tags["White"] = raw
            let exported = PGNExporter.export(game: Game(), tags: tags)
            let reparsed = PGNParser.parse(exported)
            XCTAssertEqual(reparsed.count, 1, "value: \(raw)")
            XCTAssertEqual(reparsed[0].white, raw,
                           "round-trip must be exact for: \(raw)\nexported:\n\(exported)")
        }
    }

    func testSANUCIRoundTrip() {
        let pos = Position.initial()
        // e4 as SAN -> Move -> UCI
        XCTAssertEqual(UCIParser.sanToUCI("e4", in: pos), "e2e4")
        // e2e4 as UCI -> SAN
        XCTAssertEqual(UCIParser.uciToSAN("e2e4", in: pos), "e4")
        let move = PGNParser.parseMove("e4", in: pos)
        XCTAssertEqual(move?.uci, "e2e4")
        XCTAssertNil(UCIParser.uciToMove("e2e4junk", in: pos))
        XCTAssertNil(UCIParser.uciToMove("e2e4q", in: pos))
    }

    func testUCIPromotionRequiresAValidExplicitPiece() throws {
        let position = try XCTUnwrap(Position(fen: "8/4P3/8/8/8/8/8/k6K w - - 0 1"))
        XCTAssertEqual(UCIParser.uciToMove("e7e8q", in: position)?.promotion, .queen)
        XCTAssertNil(UCIParser.uciToMove("e7e8", in: position))
        XCTAssertNil(UCIParser.uciToMove("e7e8x", in: position))
        XCTAssertNil(UCIParser.uciToMove("e7e8qq", in: position))
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
