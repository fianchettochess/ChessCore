import XCTest
@testable import ChessCore

final class MoveGeneratorTests: XCTestCase {

    /// Counts leaf nodes of the legal-move tree to `depth` — the standard
    /// "perft" correctness oracle for a move generator. Exact node counts at
    /// known positions catch castling / en-passant / promotion / check /
    /// pin bugs that spot-checks miss, and pin the generator's behavior so a
    /// future (magic-bitboard) rewrite can be proven move-equivalent.
    private func perft(_ position: Position, _ depth: Int) -> Int {
        let moves = MoveGenerator.legalMoves(for: position)
        if depth <= 1 { return depth <= 0 ? 1 : moves.count }
        var nodes = 0
        for move in moves {
            var next = position
            MoveGenerator.applyMoveUnchecked(&next, move)
            nodes += perft(next, depth - 1)
        }
        return nodes
    }

    private func assertPerft(_ fen: String, _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid FEN: \(fen)", file: file, line: line)
            return
        }
        // Deep perft is exhaustive but slow in unoptimized builds. For routine
        // debug `swift test`, cap each position at the deepest layer under a node
        // budget (perft counts grow monotonically with depth, so once one layer
        // exceeds the budget, deeper ones do too). Release verifies EVERY listed
        // depth — run `swift test -c release` for the full correctness oracle.
        #if DEBUG
        let nodeBudget = 200_000
        #else
        let nodeBudget = Int.max
        #endif
        for (i, count) in expected.enumerated() {
            if count > nodeBudget { break }
            XCTAssertEqual(perft(pos, i + 1), count, "perft(\(i + 1)) for \(fen)", file: file, line: line)
        }
    }

    func testPerftInitialPosition() {
        // 20, 400, 8902, 197281, 4865609
        assertPerft("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", [20, 400, 8902, 197281, 4865609])
    }

    func testPerftKiwipete() {
        // Heavy castling/pins/checks. 48, 2039, 97862, 4085603
        assertPerft("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862, 4085603])
    }

    func testPerftEndgameEnPassant() {
        // En-passant edge cases. 14, 191, 2812, 43238, 674624
        assertPerft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238, 674624])
    }

    func testPerftPromotionsAndChecks() {
        // Promotions + discovered checks. 6, 264, 9467
        assertPerft("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467])
    }

    func testPerftPosition5() {
        // Promotion / castling-rights stress. 44, 1486, 62379
        assertPerft("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379])
    }

    func testSANDisambiguationAndCheck() {
        // Two knights can reach d2; SAN must disambiguate by file/rank.
        let pos = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        let castleK = Move(from: Square(algebraic: "e1")!, to: Square(algebraic: "g1")!, piece: .king, isCastling: true)
        XCTAssertEqual(MoveGenerator.algebraicNotation(for: castleK, in: pos), "O-O")
        let castleQ = Move(from: Square(algebraic: "e1")!, to: Square(algebraic: "c1")!, piece: .king, isCastling: true)
        XCTAssertEqual(MoveGenerator.algebraicNotation(for: castleQ, in: pos), "O-O-O")
    }

    func testCheckAndMateDetection() {
        // Fool's mate position: 1.f3 e5 2.g4 Qh4#
        let pos = Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")!
        XCTAssertTrue(MoveGenerator.isInCheck(pos))
        XCTAssertFalse(MoveGenerator.hasAnyLegalMove(for: pos)) // checkmate
    }

    /// Proves every EMBEDDED magic is valid: each relevant-occupancy subset maps
    /// to an index whose stored attack set is the true one (collisions allowed
    /// only when they agree). A bad paste fails here, loudly, instead of silently
    /// corrupting move generation. Cheap enough to run in the normal suite.
    func testEmbeddedMagicsAreCollisionFree() {
        for isRook in [true, false] {
            let magics = isRook ? MagicTables.rookMagics : MagicTables.bishopMagics
            XCTAssertEqual(magics.count, 64)
            for sq in 0..<64 {
                let mask = MagicTables.relevantMask(square: sq, isRook: isRook)
                let bits = popcount(mask)
                let count = 1 << bits
                let shift = UInt64(64 - bits)
                let magic = magics[sq]
                var used = [Bitboard?](repeating: nil, count: count)
                for i in 0..<count {
                    let occ = MagicTables.occupancyForIndex(i, mask: mask)
                    let ref = MagicTables.slidingAttacks(square: sq, occupancy: occ, isRook: isRook)
                    let idx = Int((occ &* magic) >> shift)
                    if let existing = used[idx] {
                        XCTAssertEqual(existing, ref,
                            "magic collision at \(isRook ? "rook" : "bishop") sq \(sq), idx \(idx)")
                    } else {
                        used[idx] = ref
                    }
                }
            }
        }
    }

    /// Dev-only: runs the magic SEARCH and prints valid magics as Swift literals
    /// for embedding into MagicBitboards.swift. Run in release with
    /// `DUMP_MAGICS=1 swiftly run swift test -c release --filter testDumpMagics`.
    /// No-op otherwise so it never slows the normal suite.
    func testDumpMagics() {
        guard ProcessInfo.processInfo.environment["DUMP_MAGICS"] != nil else { return }
        var prng = MagicTables.XorShift64(seed: 0x2545F4914F6CDD1D)
        let rook = MagicTables.searchAll(isRook: true, prng: &prng)
        let bishop = MagicTables.searchAll(isRook: false, prng: &prng)
        func fmt(_ magics: [Bitboard]) -> String {
            var lines: [String] = []
            for row in stride(from: 0, to: 64, by: 4) {
                let chunk = (row..<min(row + 4, 64)).map { String(format: "0x%016llX", magics[$0]) }
                lines.append("    " + chunk.joined(separator: ", ") + ",")
            }
            return lines.joined(separator: "\n")
        }
        print("===ROOK_MAGICS_BEGIN===")
        print(fmt(rook))
        print("===ROOK_MAGICS_END===")
        print("===BISHOP_MAGICS_BEGIN===")
        print(fmt(bishop))
        print("===BISHOP_MAGICS_END===")
    }
}
