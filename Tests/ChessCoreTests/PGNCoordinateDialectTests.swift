import Testing
@testable import ChessCore

/// The ChessUp mobile app exports PGN whose movetext is a coordinate dialect
/// rather than standard SAN: `d2d4` (pawn push as from-to), `Bb4c3` (capture
/// without `x`), `Ke8g8` (castling as a two-square king move), and `a7b8q`
/// (promotion without `=`). Most of these already resolve through the SAN
/// disambiguation path; the promotion form needs the lenient no-equals
/// trailing-piece-letter handling. This suite locks the whole dialect in.
@Suite("ChessUp coordinate-dialect PGN")
struct PGNCoordinateDialectTests {

    @Test("Promotion without '=' parses in both dialects")
    func promotionWithoutEquals() throws {
        // White pawn on b7 promotes; black rook on a8 capturable.
        let position = try #require(Position(fen: "r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1"))
        // Coordinate dialect (lowercase suffix).
        #expect(PGNParser.parseMove("b7a8q", in: position)?.uci == "b7a8q")
        #expect(PGNParser.parseMove("b7b8n", in: position)?.uci == "b7b8n")
        // Lenient SAN (uppercase suffix, no '=').
        #expect(PGNParser.parseMove("bxa8Q", in: position)?.uci == "b7a8q")
        #expect(PGNParser.parseMove("b8R", in: position)?.uci == "b7b8r")
        // Standard SAN still exact.
        #expect(PGNParser.parseMove("b8=Q", in: position)?.uci == "b7b8q")
        // The suffix is a requirement, not a hint: a bare push where only
        // promotions are legal stays nil (never silently queens).
        #expect(PGNParser.parseMove("b8", in: position) == nil)
    }

    @Test("Castling as a two-square king move parses")
    func castlingAsKingMove() throws {
        let position = try #require(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        #expect(PGNParser.parseMove("Ke1g1", in: position)?.isCastling == true)
        #expect(PGNParser.parseMove("Ke1c1", in: position)?.isCastling == true)
        var black = position
        black.activeColor = .black
        #expect(PGNParser.parseMove("Ke8g8", in: black)?.isCastling == true)
    }

    @Test("A full ChessUp app export replays end to end")
    func fullChessUpExportParses() {
        // A real 49-move ChessUp OTB export (QGD Exchange → R+P endgame with a
        // no-equals promotion at move 38). 98 plies, every dialect form present.
        let moveText = """
        1. d2d4 d7d5 2. c2c4 c7c6 3. Nb1c3 Ng8f6 4. Ng1f3 Bc8g4 5. Bc1g5 e7e6
        6. e2e3 Bf8b4 7. a2a3 Bb4c3 8. b2c3 Ke8g8 9. c4d5 c6d5 10. Bf1d3 Nb8c6
        11. Ke1g1 Rf8e8 12. Qd1b3 Ra8b8 13. Nf3d2 h7h6 14. Bg5f6 Qd8f6 15. h2h3 Bg4f5
        16. Bd3f5 Qf6f5 17. g2g4 Qf5f6 18. f2f4 Nc6a5 19. Qb3b5 Na5c4 20. Nd2c4 d5c4
        21. Qb5c4 Re8c8 22. Qc4d3 a7a6 23. f4f5 e6f5 24. Rf1f5 Qf6e6 25. d4d5 Qe6e8
        26. e3e4 b7b5 27. a3a4 b5b4 28. c3b4 Rb8b4 29. Qd3a6 Rc8c4 30. a4a5 Rc4e4
        31. Qa6c6 Qe8c6 32. d5c6 Rb4c4 33. a5a6 Rc4c6 34. a6a7 Rc6c8 35. Rf5c5 Rc8a8
        36. Rc5b5 Re4e7 37. Rb5b8 Ra8b8 38. a7b8q Kg8h7 39. Ra1a7 Re7e1 40. Kg1g2 Re1e2
        41. Kg2f3 Re2h2 42. Kf3g3 Rh2c2 43. h3h4 Rc2c3 44. Kg3f4 Rc3c4 45. Kf4f5 Rc4c5
        46. Kf5f4 Rc5c4 47. Kf4g3 Rc4c3 48. Kg3h2 Rc3c2 49. Kh2g3 Rc2c3 1/2-1/2
        """
        let parsed = PGNParser.mainLineSnapshot(fromMoveText: moveText)
        #expect(parsed.moves.count == 98,
                "Expected all 98 plies to parse; got \(parsed.moves.count)")
        // Spot-check the landmarks: both castlings and the promotion.
        #expect(parsed.moves.contains { $0.move.uci == "e8g8" && $0.move.isCastling })
        #expect(parsed.moves.contains { $0.move.uci == "e1g1" && $0.move.isCastling })
        #expect(parsed.moves.contains { $0.move.uci == "a7b8q" && $0.move.promotion == .queen })
    }
}
