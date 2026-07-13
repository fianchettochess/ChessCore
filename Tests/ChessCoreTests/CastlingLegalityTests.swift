import XCTest
@testable import ChessCore

// Tests for `MoveGenerator.legalCastlingUCIs(for:)`.
//
// Correctness contract: for every position, the result must equal
//   Set(MoveGenerator.legalMoves(for: pos).filter(\.isCastling).map(\.uci))
// Every test calls assertEquivalence, which verifies both directions.
final class CastlingLegalityTests: XCTestCase {

    // MARK: - Equivalence helper

    private func oracle(for pos: Position) -> Set<String> {
        Set(MoveGenerator.legalMoves(for: pos).filter(\.isCastling).map(\.uci))
    }

    /// Assert that the fast path returns exactly the same set as the oracle.
    private func assertEquivalence(
        _ fen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid FEN: \(fen)", file: file, line: line)
            return
        }
        let fast = MoveGenerator.legalCastlingUCIs(for: pos)
        let ref  = oracle(for: pos)
        XCTAssertEqual(fast, ref,
            "legalCastlingUCIs mismatch for FEN \(fen)", file: file, line: line)
    }

    // MARK: - Corpus

    func testInitialPosition() {
        // Starting position: all pieces on first / second rank block every path.
        assertEquivalence("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }

    func testBothSidesBothColors_whiteMoves() {
        // Open back ranks, all four rights present, white to move.
        // Expected: { "e1g1", "e1c1" }
        assertEquivalence("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    }

    func testBothSidesBothColors_blackMoves() {
        // Same board, black to move. Expected: { "e8g8", "e8c8" }
        assertEquivalence("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
    }

    func testOnlyKingsideRight_white() {
        assertEquivalence("r3k2r/8/8/8/8/8/8/R3K2R w Kkq - 0 1")
    }

    func testOnlyQueensideRight_white() {
        assertEquivalence("r3k2r/8/8/8/8/8/8/R3K2R w Qkq - 0 1")
    }

    func testNoRights() {
        assertEquivalence("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1")
    }

    func testKingInCheck_noCastle() {
        // Black rook on e8 gives check to white king on e1 — no castling.
        assertEquivalence("4r3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    }

    func testKingsideTransit_fAttacked() {
        // Black rook on f8 attacks f1 — kingside blocked, queenside legal.
        assertEquivalence("5r2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    }

    func testKingsideDestination_gAttacked() {
        // Black rook on g8 attacks g1 — kingside blocked, queenside legal.
        assertEquivalence("6r1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    }

    func testQueensideTransit_dAttacked() {
        // Black rook on d8 attacks d1 — queenside blocked, kingside legal.
        assertEquivalence("3r4/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    }

    func testQueensideDestination_cAttacked() {
        // Black rook on c8 attacks c1 — queenside blocked, kingside legal.
        assertEquivalence("2r5/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    }

    func testQueensidePathBlocked_bSquareOccupied() {
        // Knight on b1 blocks the rook's queenside passage.
        // Expected: only kingside legal ("e1g1").
        assertEquivalence("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1")
    }

    func testAfterKingsideCastle_kingNotOnHomeSquare() {
        // White king already on g1 (post-castle), no white rights.
        // Expected: empty (king not on e1).
        assertEquivalence("r3k2r/8/8/8/8/8/8/5RK1 w kq - 0 1")
    }

    func testKiwipete() {
        // Standard heavy castling/pins/checks perft position — both sides have rights.
        assertEquivalence("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    }

    func testKiwipete_black() {
        assertEquivalence("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R b KQkq - 0 1")
    }

    func testPromoPosition5() {
        // Perft position 5 — white has rights but one rook replaced by queen after promo.
        assertEquivalence("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
    }

    func testBSquareAttackedButQueensideStillLegal() {
        // b1 is attacked (black rook on b8) but not required to be safe — only the
        // king's path (e1, d1, c1) must be attack-free. Queenside should be legal.
        assertEquivalence("1r6/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    }

    // MARK: - Stale rights without a rook (regression)

    /// Regression: castling was generated from rights + empty path + attack
    /// checks alone, never verifying a FRIENDLY ROOK actually sits on the
    /// corner square. A FEN with stale rights (board-setup sheet, imported
    /// [FEN] PGN) offered a phantom castle; isLegal then OR'd a phantom rook
    /// bit for the check test and applyMoveUnchecked moved whatever occupied
    /// the corner (nothing — or even an enemy piece) onto f1/d1.
    private func assertNoCastlingGenerated(
        _ fen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid FEN: \(fen)", file: file, line: line)
            return
        }
        let generated = MoveGenerator.legalMoves(for: pos).filter(\.isCastling)
        XCTAssertTrue(generated.isEmpty,
            "castling generated with no corner rook for FEN \(fen): \(generated.map(\.uci))",
            file: file, line: line)
        XCTAssertTrue(MoveGenerator.legalCastlingUCIs(for: pos).isEmpty,
            "legalCastlingUCIs offered castling with no corner rook for FEN \(fen)",
            file: file, line: line)
    }

    func testStaleKingsideRightNoRook_white() {
        assertNoCastlingGenerated("4k3/8/8/8/8/8/8/4K3 w K - 0 1")
    }

    func testStaleQueensideRightNoRook_white() {
        assertNoCastlingGenerated("4k3/8/8/8/8/8/8/4K3 w Q - 0 1")
    }

    func testStaleQueensideRightRookOnWrongCorner_black() {
        // Black has the queenside right but the only rook is on h8.
        assertNoCastlingGenerated("4k2r/8/8/8/8/8/8/4K3 b q - 0 1")
    }

    func testStaleRightEnemyPieceOnCorner_white() {
        // Black bishop on h1: previously "castling" would move the ENEMY
        // bishop to f1.
        assertNoCastlingGenerated("4k3/8/8/8/8/8/8/4K2b w K - 0 1")
    }

    func testStaleRightFriendlyNonRookOnCorner_white() {
        // White knight on h1 is not a rook — no castle.
        assertNoCastlingGenerated("4k3/8/8/8/8/8/8/4K2N w K - 0 1")
    }

    func testRookPresentStillCastles_bothWings() {
        // Guard against over-restriction: real rooks on the corners must
        // still castle.
        guard let pos = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1") else {
            return XCTFail("invalid FEN")
        }
        let ucis = Set(MoveGenerator.legalMoves(for: pos).filter(\.isCastling).map(\.uci))
        XCTAssertEqual(ucis, ["e1g1", "e1c1"])
        XCTAssertEqual(MoveGenerator.legalCastlingUCIs(for: pos), ["e1g1", "e1c1"])
    }

    // MARK: - Defense in depth: hand-constructed castling Moves (bypass generation)

    /// C9: generation now requires the corner rook, but a castling `Move` can
    /// be constructed by hand (or arrive from a corrupted/foreign source) and
    /// go straight to `isLegal` / `applyMoveUnchecked`. Legality must fail
    /// defensively — never OR a phantom rook bit into the check test — and
    /// `applyMoveUnchecked` must reject the move whole rather than create or
    /// move a phantom piece.
    private func handMadeCastle(_ from: String, _ to: String) -> Move {
        Move(from: Square(algebraic: from)!, to: Square(algebraic: to)!,
             piece: .king, isCastling: true)
    }

    private func assertPhantomCastleRejected(
        _ fen: String,
        _ move: Move,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid FEN: \(fen)", file: file, line: line)
            return
        }
        XCTAssertFalse(BitBoard(pos).isLegal(move),
            "isLegal must fail defensively without a friendly corner rook: \(fen)",
            file: file, line: line)
        var applied = pos
        MoveGenerator.applyMoveUnchecked(&applied, move)
        XCTAssertEqual(applied.fen, pos.fen,
            "applyMoveUnchecked must reject a rookless castle whole (no mutation): \(fen)",
            file: file, line: line)
    }

    func testHandMadeCastleMissingCornerRook() {
        assertPhantomCastleRejected("4k3/8/8/8/8/8/8/4K3 w K - 0 1",
                                    handMadeCastle("e1", "g1"))
        assertPhantomCastleRejected("4k3/8/8/8/8/8/8/4K3 w Q - 0 1",
                                    handMadeCastle("e1", "c1"))
        assertPhantomCastleRejected("4k3/8/8/8/8/8/8/4K3 b kq - 0 1",
                                    handMadeCastle("e8", "g8"))
    }

    func testHandMadeCastleEnemyPieceOnCorner() {
        // Black bishop on h1: applyMoveUnchecked used to move the ENEMY
        // bishop onto f1.
        assertPhantomCastleRejected("4k3/8/8/8/8/8/8/4K2b w K - 0 1",
                                    handMadeCastle("e1", "g1"))
        // White rook on a8 is the WRONG COLOR for black's queenside castle.
        assertPhantomCastleRejected("R3k3/8/8/8/8/8/8/4K3 b q - 0 1",
                                    handMadeCastle("e8", "c8"))
    }

    func testHandMadeCastleFriendlyNonRookOnCorner() {
        assertPhantomCastleRejected("4k3/8/8/8/8/8/8/4K2N w K - 0 1",
                                    handMadeCastle("e1", "g1"))
        assertPhantomCastleRejected("n3k3/8/8/8/8/8/8/4K3 b q - 0 1",
                                    handMadeCastle("e8", "c8"))
    }

    func testHandMadeCastleWithRealRookStillApplies() {
        // Over-restriction guard: the same hand-made move with a genuine
        // friendly rook on the corner must stay legal and apply fully.
        guard let pos = Position(fen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1") else {
            return XCTFail("invalid FEN")
        }
        let move = handMadeCastle("e1", "g1")
        XCTAssertTrue(BitBoard(pos).isLegal(move))
        var applied = pos
        MoveGenerator.applyMoveUnchecked(&applied, move)
        XCTAssertEqual(applied[Square(algebraic: "g1")!]?.type, .king)
        XCTAssertEqual(applied[Square(algebraic: "f1")!]?.type, .rook)
        XCTAssertNil(applied[Square(algebraic: "h1")!])
        XCTAssertNil(applied[Square(algebraic: "e1")!])
    }

    // MARK: - Randomised playout sweep (fixed seed, ~300 positions)

    func testRandomPlayoutEquivalence() {
        // XorShift64 PRNG — same sequence on every run, deterministic, no flakiness.
        var seed: UInt64 = 0xDEADBEEFCAFEBABE
        func next() -> UInt64 {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return seed
        }

        let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        var failures = 0
        let trials   = 300

        for trial in 0..<trials {
            guard var pos = Position(fen: startFEN) else { continue }
            let plies = Int(next() % 40) + 1
            var played = 0
            for _ in 0..<plies {
                let legal = MoveGenerator.legalMoves(for: pos)
                guard !legal.isEmpty else { break }
                let move = legal[Int(next() % UInt64(legal.count))]
                MoveGenerator.applyMoveUnchecked(&pos, move)
                played += 1
            }
            let fast = MoveGenerator.legalCastlingUCIs(for: pos)
            let ref  = oracle(for: pos)
            if fast != ref {
                failures += 1
                XCTFail("""
                    Trial \(trial) (after \(played) plies):
                      FEN : \(pos.fen)
                      fast: \(fast.sorted())
                      ref : \(ref.sorted())
                    """)
            }
        }
        XCTAssertEqual(failures, 0,
            "\(failures)/\(trials) equivalence failures in random playout sweep")
    }

    // MARK: - Benchmark (manual timing, always passes; speedup reported to stdout)

    func testCastlingSpeedup() {
        // Kiwipete: both colours have rights + many legal moves — a demanding position
        // for the full generator, and still fast for the castling-only path.
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        guard let pos = Position(fen: fen) else { XCTFail("bad FEN"); return }
        let N = 10_000

        // Warm up.
        for _ in 0..<100 {
            _ = MoveGenerator.legalMoves(for: pos).filter(\.isCastling).map(\.uci)
            _ = MoveGenerator.legalCastlingUCIs(for: pos)
        }

        let t0 = Date()
        for _ in 0..<N { _ = MoveGenerator.legalMoves(for: pos).filter(\.isCastling).map(\.uci) }
        let tFull = Date().timeIntervalSince(t0)

        let t1 = Date()
        for _ in 0..<N { _ = MoveGenerator.legalCastlingUCIs(for: pos) }
        let tFast = Date().timeIntervalSince(t1)

        let speedup = tFull / max(tFast, 1e-12)
        let fullUs  = tFull  * 1_000_000 / Double(N)
        let fastUs  = tFast  * 1_000_000 / Double(N)
        print(String(format: """

            [CastlingSpeedup] legalMoves+filter vs legalCastlingUCIs (%d iters, kiwipete)
              full : %.2f µs/call
              fast : %.2f µs/call
              speedup: %.1f×
            """, N, fullUs, fastUs, speedup))

        // The fast path should be at least 2× faster even in debug builds.
        XCTAssertGreaterThan(speedup, 2.0,
            "Expected at least 2× speedup; got \(String(format: "%.1f", speedup))×")
    }
}
