import Testing
@testable import ChessCore

/// Regression coverage for the pre-public audit: malformed/degenerate input must
/// never crash the engine, and the draw-state paths (stalemate, move-count
/// rules, insufficient material) that shipped untested.
@Suite("Release hardening")
struct ReleaseHardeningTests {

    // MARK: Malformed input must not crash (the parser is lenient; the engine is total)

    @Test("A kingless FEN yields no legal moves and a safe game state (no crash)")
    func kinglessFENIsTotal() throws {
        // The bitboard king lookup in the legality filter previously indexed the
        // attack tables out of bounds when the side to move had no king.
        let pos = try #require(Position(fen: "8/8/8/8/8/8/4P3/8 w - - 0 1"))
        #expect(MoveGenerator.legalMoves(for: pos).isEmpty)

        let game = Game()
        #expect(game.loadFEN("8/8/8/8/8/8/4P3/8 w - - 0 1"))
        // No king to be in check + no legal moves → reported as stalemate, but the
        // point of the test is that reading gameState does not trap.
        #expect(game.gameState == .stalemate)
    }

    @Test("A SAN token ending in a multi-grapheme uppercase char parses to nil, not a crash")
    func multiGraphemeSANDoesNotCrash() {
        // "ß".uppercased() == "SS": forming a Character from it used to trap.
        #expect(PGNParser.parseMove("abß", in: .initial()) == nil)
        #expect(PGNParser.parseMove("e4ﬀ", in: .initial()) == nil)
        // A real promotion letter still parses (guard didn't over-reject).
        let promo = try! #require(Position(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"))
        #expect(PGNParser.parseMove("a8Q", in: promo)?.promotion == .queen)
    }

    @Test("A phantom en-passant target in a FEN produces no illegal EP move")
    func phantomEnPassantIsSanitized() throws {
        // e6 is claimed as an EP target but there is no black pawn on e5 to
        // capture; move generation must not emit an en-passant capture of nothing.
        let pos = try #require(Position(fen: "4k3/8/8/3P4/8/8/8/4K3 w - e6 0 1"))
        #expect(!MoveGenerator.legalMoves(for: pos).contains { $0.isEnPassant })
        // A genuine EP target (real pawn present) is still honored.
        let real = try #require(Position(fen: "4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1"))
        #expect(MoveGenerator.legalMoves(for: real).contains { $0.isEnPassant && $0.to.algebraic == "e6" })
    }

    // MARK: Draw-state coverage

    @Test("Stalemate is detected (no legal move, not in check)")
    func stalemateDetected() {
        let game = Game()
        #expect(game.loadFEN("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(game.gameState == .stalemate)
    }

    @Test("The fifty-move threshold makes a draw claimable, not automatic")
    func fiftyMoveDrawIsClaimable() {
        // Sufficient material + legal moves available, with 50 reversible moves
        // by each side recorded in the halfmove clock.
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 100 1"))
        #expect(game.gameState == .playing)
        #expect(game.canClaimDrawByFiftyMoveRule)
    }

    @Test("The fifty-move claim has exact lower and upper boundaries")
    func fiftyMoveClaimBoundaries() {
        let game = Game()

        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 99 1"))
        #expect(!game.canClaimDrawByFiftyMoveRule)
        #expect(game.gameState == .playing)

        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 149 1"))
        #expect(game.canClaimDrawByFiftyMoveRule)
        #expect(game.gameState == .playing)

        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 150 1"))
        #expect(!game.canClaimDrawByFiftyMoveRule)
        #expect(game.gameState == .draw)
    }

    @Test("The seventy-five-move threshold is an automatic draw")
    func seventyFiveMoveDrawIsAutomatic() {
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 150 1"))
        #expect(game.gameState == .draw)

        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 175 1"))
        #expect(game.gameState == .draw)
    }

    @Test("Checkmate takes precedence when the 150th reversible halfmove mates")
    func checkmatePrecedesSeventyFiveMoveDraw() throws {
        let game = Game()
        #expect(game.loadFEN("7k/5Q2/6K1/8/8/8/8/8 w - - 149 1"))

        let mate = try #require(UCIParser.uciToMove("f7g7", in: game.legalMoves))
        game.apply(mate)

        #expect(game.position.halfmoveClock == 150)
        #expect(game.gameState == .checkmate)
        #expect(!game.canClaimDrawByFiftyMoveRule)
    }

    @Test("Reversible moves increment the halfmove clock into claim territory")
    func reversibleMoveIncrementsHalfmoveClock() throws {
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 99 1"))

        let move = try #require(UCIParser.uciToMove("a2a3", in: game.legalMoves))
        game.apply(move)

        #expect(game.position.halfmoveClock == 100)
        #expect(game.canClaimDrawByFiftyMoveRule)
        #expect(game.gameState == .playing)
    }

    @Test("Pawn moves reset the halfmove clock and cancel a pending claim")
    func pawnMoveResetsHalfmoveClock() throws {
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/P7/R3K3 w - - 149 1"))
        #expect(game.canClaimDrawByFiftyMoveRule)

        let move = try #require(UCIParser.uciToMove("a2a3", in: game.legalMoves))
        game.apply(move)

        #expect(game.position.halfmoveClock == 0)
        #expect(!game.canClaimDrawByFiftyMoveRule)
        #expect(game.gameState == .playing)
    }

    @Test("Captures reset the halfmove clock and cancel a pending claim")
    func captureResetsHalfmoveClock() throws {
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/Rr6/4K3 w - - 149 1"))
        #expect(game.canClaimDrawByFiftyMoveRule)

        let capture = try #require(UCIParser.uciToMove("a2b2", in: game.legalMoves))
        #expect(capture.capturedPiece == .rook)
        game.apply(capture)

        #expect(game.position.halfmoveClock == 0)
        #expect(!game.canClaimDrawByFiftyMoveRule)
        #expect(game.gameState == .playing)
    }

    @Test("Insufficient-material detection, including the bishop-colour rule")
    func insufficientMaterial() throws {
        func insufficient(_ fen: String) throws -> Bool {
            try #require(Position(fen: fen)).hasInsufficientMaterial
        }
        // K vs K, K+minor vs K.
        #expect(try insufficient("4k3/8/8/8/8/8/8/4K3 w - - 0 1"))
        #expect(try insufficient("4k3/8/8/8/8/8/8/3NK3 w - - 0 1"))   // K+N vs K
        #expect(try insufficient("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1"))   // K+B vs K
        // K+B vs K+B, bishops on the SAME colour → dead → insufficient.
        #expect(try insufficient("b3k3/8/8/8/8/8/B7/4K3 w - - 0 1"))
        // K+B vs K+B, OPPOSITE colours → not an auto-draw.
        #expect(try !insufficient("4k3/b7/8/8/8/8/B7/4K3 w - - 0 1"))
        // A rook is sufficient.
        #expect(try !insufficient("4k3/8/8/8/8/8/R7/4K3 w - - 0 1"))
    }
}
