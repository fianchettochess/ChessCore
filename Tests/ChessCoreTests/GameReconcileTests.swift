import XCTest
@testable import ChessCore

/// Covers `Game.reconcile(toPlacementOf:)` — history-preserving correction of the
/// game to a target board state. Contract: a reachable target EXTENDS the existing
/// move tree (history preserved); an unreachable target leaves the game untouched.
final class GameReconcileTests: XCTestCase {

    private func gameAfter(_ ucis: [String]) -> Game {
        let game = Game()
        for uci in ucis {
            let move = UCIParser.uciToMove(uci, in: MoveGenerator.legalMoves(for: game.position))!
            game.apply(move)
        }
        return game
    }

    private func position(_ base: Position, plus uci: String) -> Position {
        var p = base
        let move = UCIParser.uciToMove(uci, in: MoveGenerator.legalMoves(for: p))!
        MoveGenerator.applyMoveUnchecked(&p, move)
        return p
    }

    private func placement(_ p: Position) -> Substring { p.fen.split(separator: " ").first ?? "" }

    /// One missed move (the common drift): history is preserved and EXTENDED by the
    /// inferred move, and the position now matches the board.
    func testOneMoveDriftPreservesAndExtendsHistory() {
        let game = gameAfter(["e2e4", "e7e5", "g1f3", "b8c6"])
        XCTAssertEqual(game.moveHistory.count, 4)

        let board = position(game.position, plus: "f1b5")   // white played Bb5; app missed it
        XCTAssertTrue(game.reconcile(toPlacementOf: board))

        XCTAssertEqual(game.moveHistory.count, 5, "the missed move should be appended, not reset")
        XCTAssertEqual(placement(game.position), placement(board))
        XCTAssertFalse(game.rootChildren.isEmpty)
    }

    /// A two-move gap still reconciles and keeps every prior move.
    func testTwoMoveDriftKeepsHistory() {
        let game = gameAfter(["e2e4", "e7e5", "g1f3", "b8c6"])
        var board = position(game.position, plus: "f1b5")
        board = position(board, plus: "a7a6")              // Bb5 a6 happened on the board
        XCTAssertTrue(game.reconcile(toPlacementOf: board, maxPly: 4))
        XCTAssertEqual(game.moveHistory.count, 6)
        XCTAssertEqual(placement(game.position), placement(board))
    }

    /// Already in sync: no-op success, no spurious moves.
    func testAlreadyInSyncIsNoOp() {
        let game = gameAfter(["e2e4", "e7e5"])
        XCTAssertTrue(game.reconcile(toPlacementOf: game.position))
        XCTAssertEqual(game.moveHistory.count, 2)
    }

    /// Unreachable target: returns false and does NOT mutate (caller may hard-reset).
    func testUnreachableReturnsFalseWithoutMutation() {
        let game = gameAfter(["e2e4", "e7e5", "g1f3"])
        let before = game.moveHistory.count
        let unrelated = Position(fen: "8/8/8/3k4/8/3K4/8/8 w - - 0 1")!
        XCTAssertFalse(game.reconcile(toPlacementOf: unrelated, maxPly: 3))
        XCTAssertEqual(game.moveHistory.count, before, "no moves should be applied when unreachable")
    }
}
