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
