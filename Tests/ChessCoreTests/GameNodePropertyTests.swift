import XCTest
@testable import ChessCore

/// Covers the node-property invalidation counter (`nodePropertyVersion`) and the
/// `reconcilePath(toPlacementOf:)` pure query. Contract: every node-property
/// setter bumps the counter exactly once; structural edits and navigation do NOT
/// touch it; and `reconcile` ≡ "apply every move of `reconcilePath`".
final class GameNodePropertyTests: XCTestCase {

    private func gameAfter(_ ucis: [String]) -> Game {
        let game = Game()
        for uci in ucis {
            let move = UCIParser.uciToMove(uci, in: MoveGenerator.legalMoves(for: game.position))!
            game.apply(move)
        }
        return game
    }

    // MARK: - nodePropertyVersion bump semantics

    func testEachSetterBumpsExactlyOnce() {
        let game = gameAfter(["e2e4", "e7e5"])
        let node = game.currentNode!

        var expected = game.nodePropertyVersion

        game.setAnnotation(.brilliant, on: node)
        expected += 1
        XCTAssertEqual(game.nodePropertyVersion, expected)
        XCTAssertEqual(node.annotation, .brilliant)

        game.setComment("book move", on: node)
        expected += 1
        XCTAssertEqual(game.nodePropertyVersion, expected)
        XCTAssertEqual(node.comment, "book move")

        game.clearComment(on: node)
        expected += 1
        XCTAssertEqual(game.nodePropertyVersion, expected)
        XCTAssertNil(node.comment)

        game.setEngineResults(on: node, bestMoveUCI: "g1f3", eval: "+0.3")
        expected += 1
        XCTAssertEqual(game.nodePropertyVersion, expected)
        XCTAssertEqual(node.engineBestMoveUCI, "g1f3")
        XCTAssertEqual(node.engineEval, "+0.3")

        game.setMoveQuality(.excellent, accuracy: 97.5, on: node)
        expected += 1
        XCTAssertEqual(game.nodePropertyVersion, expected)
        XCTAssertEqual(node.moveQuality, .excellent)
        XCTAssertEqual(node.moveAccuracy, 97.5)

        game.bumpNodeProperty()
        expected += 1
        XCTAssertEqual(game.nodePropertyVersion, expected)
    }

    func testStructuralEditsAndNavigationDoNotBumpNodePropertyVersion() {
        let game = gameAfter(["e2e4", "e7e5", "g1f3"])
        let before = game.nodePropertyVersion

        // Navigation
        game.undoMove()
        game.redoMove()
        XCTAssertEqual(game.nodePropertyVersion, before)

        // Structural edit (bumps treeMutationCount, not nodePropertyVersion)
        let treeBefore = game.treeMutationCount
        game.deleteFromNode(game.currentNode!)
        XCTAssertGreaterThan(game.treeMutationCount, treeBefore)
        XCTAssertEqual(game.nodePropertyVersion, before)
    }

    func testSetterBumpDoesNotTouchTreeMutationCount() {
        let game = gameAfter(["e2e4"])
        let treeBefore = game.treeMutationCount
        game.setAnnotation(.mistake, on: game.currentNode!)
        XCTAssertEqual(game.treeMutationCount, treeBefore)
    }

    // MARK: - reconcilePath parity with reconcile

    func testReconcilePathEmptyWhenAlreadyMatching() {
        let game = gameAfter(["e2e4", "e7e5"])
        XCTAssertEqual(game.reconcilePath(toPlacementOf: game.position), [])
    }

    func testReconcilePathNilWhenUnreachable() {
        let game = Game()
        // A position that cannot be reached from the start in the default
        // 4-ply budget: white king teleported to e5.
        let unreachable = Position(fen: "rnbqkbnr/pppppppp/8/4K3/8/8/PPPPPPPP/RNBQ1BNR b kq - 0 1")!
        XCTAssertNil(game.reconcilePath(toPlacementOf: unreachable))
    }

    func testReconcileEqualsApplyingReconcilePath() {
        // Target two plies ahead of the game: path query then manual apply must
        // land on the same position AND the same history as reconcile itself.
        let pathGame = gameAfter(["e2e4", "e7e5"])
        let reconcileGame = gameAfter(["e2e4", "e7e5"])
        var target = pathGame.position
        for uci in ["g1f3", "b8c6"] {
            let move = UCIParser.uciToMove(uci, in: MoveGenerator.legalMoves(for: target))!
            MoveGenerator.applyMoveUnchecked(&target, move)
        }

        guard let path = pathGame.reconcilePath(toPlacementOf: target) else {
            return XCTFail("path unexpectedly nil")
        }
        XCTAssertFalse(path.isEmpty)
        for move in path { pathGame.apply(move) }

        XCTAssertTrue(reconcileGame.reconcile(toPlacementOf: target))
        XCTAssertEqual(pathGame.position.fen, reconcileGame.position.fen)
        XCTAssertEqual(pathGame.moveHistory.map(\.notation),
                       reconcileGame.moveHistory.map(\.notation))
    }
}
