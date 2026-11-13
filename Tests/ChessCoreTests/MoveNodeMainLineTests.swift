import XCTest
@testable import ChessCore

final class MoveNodeMainLineTests: XCTestCase {
    private func assertMainLine(
        _ game: Game,
        expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(game.mainLine.map(\.notation), expected, file: file, line: line)
        XCTAssertEqual(game.moveHistory.map(\.notation), expected, file: file, line: line)

        var pending = game.rootChildren
        while let node = pending.popLast() {
            let path = node.pathFromRoot().map(\.notation)
            XCTAssertEqual(
                node.isOnMainLine,
                path == Array(expected.prefix(path.count)),
                path.joined(separator: " "), file: file, line: line
            )
            // Numbering and mover color remain anchored to the position on
            // either kind of line, rather than depending on main-line status.
            XCTAssertEqual(node.moveNumber, node.plyIndex / 2 + 1, file: file, line: line)
            XCTAssertEqual(node.moverColor, node.plyIndex.isMultiple(of: 2) ? .white : .black,
                           file: file, line: line)
            pending.append(contentsOf: node.children)
        }
    }

    func testMainLineTableAndUnchangedPGNRoundTrip() throws {
        let cases: [(name: String, text: String, nodeCount: Int)] = [
            ("no root variation", "1. e4 e5 2. Nf3", 3),
            ("one root variation", "1. e4 ( 1. d4 d5 2. c4 ) e5 2. Nf3", 6),
            ("several root variations",
             "1. e4 ( 1. d4 d5 ) ( 1. c4 e5 ) ( 1. Nf3 d5 ) e5 2. Nf3", 9),
            ("nested variations",
             "1. e4 ( 1. d4 d5 ( 1... Nf6 2. c4 ) 2. c4 ) e5 ( 1... c5 2. Nf3 ) 2. Nf3", 10),
        ]
        for test in cases {
            let game = Game()
            XCTAssertTrue(game.loadPGN(test.text + " *"), test.name)
            assertMainLine(game, expected: ["e4", "e5", "Nf3"])
            XCTAssertEqual(PGNExporter.moveText(for: game.rootChildren), test.text, test.name)

            let snapshot = try GameTreeSnapshot(capturing: game)
            XCTAssertEqual(snapshot.nodes.count, test.nodeCount, test.name)
            let restored = Game()
            try restored.restore(from: snapshot)
            assertMainLine(restored, expected: ["e4", "e5", "Nf3"])
            XCTAssertEqual(try GameTreeSnapshot(capturing: restored), snapshot, test.name)

            let reloaded = try XCTUnwrap(PGNParser.loadGame(from: game.exportPGN()), test.name)
            assertMainLine(reloaded, expected: ["e4", "e5", "Nf3"])
            XCTAssertEqual(try GameTreeSnapshot(capturing: reloaded), snapshot, test.name)
        }
    }

    func testApplyingPromotingAndRemovingRootVariations() throws {
        let game = Game()
        game.apply(try XCTUnwrap(UCIParser.uciToMove("e2e4", in: game.position)))
        game.navigateToStart()
        game.applyMoveFromPGN(try XCTUnwrap(UCIParser.uciToMove("d2d4", in: game.position)))
        game.apply(try XCTUnwrap(UCIParser.uciToMove("d7d5", in: game.position)))
        let alternative = game.rootChildren[1]
        assertMainLine(game, expected: ["e4"])

        game.promoteVariation(alternative)
        assertMainLine(game, expected: ["d4", "d5"])
        game.deleteFromNode(alternative)
        assertMainLine(game, expected: ["e4"])

        // Direct edits of the public array also update root membership.
        game.rootChildren.append(alternative)
        assertMainLine(game, expected: ["e4"])
        game.rootChildren.swapAt(0, 1)
        assertMainLine(game, expected: ["d4", "d5"])
        game.navigateToNode(alternative)
        game.retractLastPlies(1)
        assertMainLine(game, expected: ["e4"])
    }

    func testBlackToMoveRootVariationsKeepAnchoredNumbering() throws {
        let game = Game()
        XCTAssertTrue(game.loadFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 34"))
        game.apply(try XCTUnwrap(UCIParser.uciToMove("e7e5", in: game.position)))
        game.navigateToStart()
        game.apply(try XCTUnwrap(UCIParser.uciToMove("d7d5", in: game.position)))
        game.apply(try XCTUnwrap(UCIParser.uciToMove("d2d4", in: game.position)))
        XCTAssertEqual(game.rootChildren.map(\.isOnMainLine), [true, false])
        let variation = game.rootChildren[1]
        XCTAssertFalse(try XCTUnwrap(variation.mainContinuation).isOnMainLine)
        XCTAssertEqual(variation.moveNumber, 34)
        XCTAssertEqual(variation.moverColor, .black)
        XCTAssertEqual(variation.mainContinuation?.moveNumber, 35)
        XCTAssertEqual(variation.mainContinuation?.moverColor, .white)

        let exported = game.exportPGN()
        XCTAssertEqual(exported.components(separatedBy: "\n\n").last,
                       "34... e5 ( 34... d5 35. d4 ) *\n")
        let reloaded = try XCTUnwrap(PGNParser.loadGame(from: exported))
        XCTAssertEqual(try GameTreeSnapshot(capturing: reloaded).nodes,
                       try GameTreeSnapshot(capturing: game).nodes)
        XCTAssertEqual(reloaded.rootChildren.map(\.isOnMainLine), [true, false])
    }

    func testRootOwnershipIsWeakAndStandaloneTreesStillWork() throws {
        weak var weakGame: Game?
        let root: MoveNode
        let tip: MoveNode
        do {
            let game = Game()
            weakGame = game
            XCTAssertTrue(game.loadPGN("1. e4 ( 1. d4 d5 ) e5 *"))
            root = try XCTUnwrap(game.rootChildren.last)
            tip = try XCTUnwrap(root.mainContinuation)
            withExtendedLifetime(game) { XCTAssertFalse(tip.isOnMainLine) }
        }
        XCTAssertNil(weakGame)
        XCTAssertTrue(root.isOnMainLine)
        XCTAssertTrue(tip.isOnMainLine)
    }
}
