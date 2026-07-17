import Testing
@testable import ChessCore

/// Regression coverage for the pre-public audit: malformed/degenerate input must
/// never crash the engine, and the draw-state paths (stalemate, fifty-move,
/// insufficient material) that shipped untested.
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

    @Test("The fifty-move rule reports a draw")
    func fiftyMoveDraw() {
        // Sufficient material + legal moves available, but halfmoveClock == 100.
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/R7/4K3 w - - 100 1"))
        #expect(game.gameState == .draw)
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
