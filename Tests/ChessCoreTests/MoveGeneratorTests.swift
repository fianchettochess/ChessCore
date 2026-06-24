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
        for (i, count) in expected.enumerated() {
            XCTAssertEqual(perft(pos, i + 1), count, "perft(\(i + 1)) for \(fen)", file: file, line: line)
        }
    }

    func testPerftInitialPosition() {
        // 20, 400, 8902, 197281
        assertPerft("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", [20, 400, 8902, 197281])
    }

    func testPerftKiwipete() {
        // Heavy castling/pins/checks. 48, 2039, 97862
        assertPerft("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862])
    }

    func testPerftEndgameEnPassant() {
        // En-passant edge cases. 14, 191, 2812, 43238
        assertPerft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238])
    }

    func testPerftPromotionsAndChecks() {
        // Promotions + discovered checks. 6, 264, 9467
        assertPerft("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467])
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
}
