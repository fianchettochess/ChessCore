import XCTest
@testable import ChessCore

final class GameTests: XCTestCase {
    private func uci(_ s: String, _ g: Game) -> Move { UCIParser.uciToMove(s, in: g.position)! }

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
