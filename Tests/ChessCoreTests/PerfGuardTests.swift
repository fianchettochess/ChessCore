import XCTest
import Foundation
import Dispatch
@testable import ChessCore

/// Perf regression guard — NORMALLY SKIPPED so the ~4s/111-test suite is
/// untouched. Opt in with `RUN_BENCH=1` and a release build:
///
///   RUN_BENCH=1 swift test -c release --filter PerfGuard
///
/// It asserts move-gen CORRECTNESS (the exact perft node count) AND a
/// conservative throughput floor set well under the measured Mnps, so it flags a
/// real regression rather than runner-to-runner jitter.
///
/// `import Foundation`/`Dispatch` are explicit because swift-corelibs XCTest
/// (Linux) does not re-export them.
final class PerfGuardTests: XCTestCase {

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

    func testPerftThroughputFloor() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_BENCH"] != nil,
                          "perf guard is opt-in: set RUN_BENCH=1 (and build -c release)")
        #if DEBUG
        throw XCTSkip("timings are meaningless in DEBUG — run: RUN_BENCH=1 swift test -c release --filter PerfGuard")
        #else
        let pos = try XCTUnwrap(
            Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        )
        let start = DispatchTime.now().uptimeNanoseconds
        let nodes = perft(pos, 5)
        let secs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        XCTAssertEqual(nodes, 4_865_609, "perft(5) node count — move generation is WRONG")
        let mnps = Double(nodes) / secs / 1_000_000
        // Floor set several-fold under a typical Apple-silicon measurement so CI
        // jitter and slower runners don't flake. Tighten once a baseline lands.
        XCTAssertGreaterThan(mnps, 8.0, "perft throughput \(mnps) Mnps fell below the regression floor")
        #endif
    }
}
