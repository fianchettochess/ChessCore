import XCTest
@testable import ChessCore

final class GameTests: XCTestCase {
    private func uci(_ s: String, _ g: Game) -> Move { UCIParser.uciToMove(s, in: g.position)! }

    // MARK: - retractLastPlies (take-back)

    func testRetractRemovesMoveSoNextIsMainline() {
        // Play e4, retract it, play f3 — f3 must be the MAIN line (not a variation
        // hanging off the retracted e4). This is the electronic-board take-back save fix.
        let g = Game()
        g.newGame()
        g.apply(uci("e2e4", g))
        g.retractLastPlies(1)
        XCTAssertNil(g.currentNode, "cursor back to start after retracting the only move")
        XCTAssertTrue(g.rootChildren.isEmpty, "the retracted move must be REMOVED from the tree")
        g.apply(uci("f2f3", g))
        XCTAssertEqual(g.rootChildren.count, 1, "only the actually-played move remains at the root")
        XCTAssertEqual(g.rootChildren.first?.notation, "f3")
        // Exported movetext must be the clean played line, no retracted-move variation.
        XCTAssertEqual(PGNExporter.moveText(for: g.rootChildren), "1. f3")
    }

    func testRetractMultiPlyRemovesWholeBranch() {
        let g = Game()
        g.newGame()
        g.apply(uci("e2e4", g))
        g.apply(uci("e7e5", g))
        g.retractLastPlies(2)            // undo both, back to start
        XCTAssertNil(g.currentNode)
        XCTAssertTrue(g.rootChildren.isEmpty, "the whole retracted branch is gone")
        g.apply(uci("d2d4", g))
        XCTAssertEqual(PGNExporter.moveText(for: g.rootChildren), "1. d4")
    }

    func testRetractPastStartIsSafe() {
        let g = Game()
        g.newGame()
        g.apply(uci("e2e4", g))
        g.retractLastPlies(5)            // more than exists
        XCTAssertNil(g.currentNode)
        XCTAssertTrue(g.rootChildren.isEmpty)
    }

    func testApplyNavigateUndoRedo() {
        let g = Game()
        g.apply(uci("e2e4", g))
        g.apply(uci("e7e5", g))
        XCTAssertEqual(g.mainLine.map(\.notation), ["e4", "e5"])
        XCTAssertEqual(g.currentMoveIndex, 1)
        g.undoMove()
        XCTAssertEqual(g.currentMoveIndex, 0)
        g.navigateToStart()
        XCTAssertNil(g.currentNode)
        XCTAssertFalse(g.canUndo)
        g.redoMove()
        XCTAssertEqual(g.currentMoveIndex, 0)
        XCTAssertEqual(g.mainLine.count, 2) // navigation doesn't prune the tree
    }

    func testFoolsMate() {
        let g = Game()
        for u in ["f2f3", "e7e5", "g2g4", "d8h4"] { g.apply(uci(u, g)) }
        XCTAssertEqual(g.gameState, .checkmate)
    }

    func testPGNRoundTrip() {
        let g = Game()
        XCTAssertTrue(g.loadPGN("1. e4 e5 2. Nf3 Nc6 3. Bb5 *"))
        XCTAssertEqual(g.mainLine.map(\.notation), ["e4", "e5", "Nf3", "Nc6", "Bb5"])
        let g2 = Game()
        XCTAssertTrue(g2.loadPGN(g.exportPGN()))
        XCTAssertEqual(g2.mainLine.map(\.notation), ["e4", "e5", "Nf3", "Nc6", "Bb5"])
    }

    func testThreefoldRepetition() {
        let g = Game()
        // Knights out and back three full times → the start position recurs.
        for _ in 0..<3 {
            for u in ["g1f3", "g8f6", "f3g1", "f6g8"] { g.apply(uci(u, g)) }
        }
        XCTAssertEqual(g.gameState, .repetition)
    }

    func testVariationEditing() {
        let g = Game()
        g.apply(uci("e2e4", g))
        g.apply(uci("e7e5", g))
        // Add a sideline from the start: 1.d4 as a variation.
        g.navigateToStart()
        g.apply(uci("d2d4", g))
        XCTAssertEqual(g.rootChildren.count, 2) // e4 (main) + d4 (variation)
        let d4 = g.rootChildren[1]
        g.promoteVariation(d4)
        XCTAssertTrue(g.rootChildren.first === d4) // d4 promoted to main
        g.deleteFromNode(d4)
        XCTAssertEqual(g.rootChildren.count, 1)
    }
}
