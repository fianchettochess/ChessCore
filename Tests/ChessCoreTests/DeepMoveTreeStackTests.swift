import XCTest
import Foundation
@testable import ChessCore

/// PGN import accepts up to `PGNParser.maximumMoveTreeNodes` moves, and apps
/// export and inspect those trees from background work, whose threads have far
/// smaller stacks than the main thread. A walk that recurses per ply crashes
/// the whole process there, so these run at the import limit on such a stack.
final class DeepMoveTreeStackTests: XCTestCase {

    private func onBackgroundStack(_ body: @escaping @Sendable () -> Void) {
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            body()
            finished.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        finished.wait()
    }

    private static let start = Position.initial()
    private static let knightMove = UCIParser.uciToMove("g1f3", in: start)!

    /// Nodes in this tree are only walked, never replayed, so they can all
    /// carry one move.
    private func makeNode(parent: MoveNode?, ply: Int) -> MoveNode {
        MoveNode(
            move: Self.knightMove,
            notation: "Nf3",
            positionBefore: Self.start,
            parent: parent,
            plyIndex: ply
        )
    }

    /// Appends a first-child chain below `node`, returning its last node.
    private func extend(_ node: MoveNode, by count: Int) -> MoveNode {
        var tip = node
        for _ in 0..<count {
            let next = makeNode(parent: tip, ply: tip.plyIndex + 1)
            tip.children.append(next)
            tip = next
        }
        return tip
    }

    func testLongestImportableLineExportsOnBackgroundStack() throws {
        let limit = PGNParser.maximumMoveTreeNodes
        let first = makeNode(parent: nil, ply: 0)
        let reply = extend(first, by: 1)
        first.children.append(makeNode(parent: first, ply: 1))
        _ = extend(reply, by: limit - 3)
        let game = Game()
        game.rootChildren = [first]

        nonisolated(unsafe) let shared = game
        nonisolated(unsafe) var exported = ""
        onBackgroundStack { exported = shared.exportPGN() }

        let movetext = try XCTUnwrap(exported.components(separatedBy: "\n\n").last)
        let words = movetext.split(whereSeparator: \.isWhitespace).map(String.init)
        XCTAssertEqual(
            Array(words.prefix(7)),
            ["1.", "Nf3", "Nf3", "(", "1...", "Nf3", ")"],
            "a variation stays beside the move it replaces"
        )
        XCTAssertEqual(words.suffix(3), ["\((limit - 2) / 2 + 1).", "Nf3", "*"], "the export reaches the last move")
    }

    func testMainLineCheckAnswersAtDepthOnBackgroundStack() {
        let depth = PGNParser.maximumMoveTreeNodes - 2
        let first = makeNode(parent: nil, ply: 0)
        let mainTip = extend(first, by: depth)

        // The only step off the main line is at the root, so the answer for
        // this tip depends on the walk reaching the far end.
        let rootAlternative = makeNode(parent: nil, ply: 0)
        let offLineTip = extend(rootAlternative, by: depth)
        let game = Game()
        game.rootChildren = [first, rootAlternative]

        nonisolated(unsafe) let onLine = mainTip
        nonisolated(unsafe) let offLine = offLineTip
        nonisolated(unsafe) var answers = (onMain: false, offMain: true)
        onBackgroundStack { answers = (onLine.isOnMainLine, offLine.isOnMainLine) }

        XCTAssertTrue(answers.onMain)
        XCTAssertFalse(answers.offMain)
        withExtendedLifetime(game) {}
    }
}
