// ChessCoreBench — release-only micro-benchmarks for ChessCore's hot paths.
//
// Invisible to library consumers (they depend on the `ChessCore` library
// product) and never pulled into the Skip/Android transpile. Run:
//
//   DEVELOPER_DIR=… swift run -c release ChessCoreBench
//
// DEBUG builds are meaningless for timing (perft is ~100x slower and inlining is
// off), so the bench warns and the values should be ignored there. `DispatchTime`
// (not `ContinuousClock`) keeps the target buildable on the package's macOS 10.15
// floor.
import ChessCore
import Dispatch

// MARK: - perft (legal-move-gen + make/unmake throughput; node counts are the
// correctness oracle — a wrong count means a move-generation bug).

func perft(_ position: Position, _ depth: Int) -> Int {
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

func timeSeconds(_ body: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
}

func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

func benchPerft(_ name: String, fen: String, depth: Int, expected: Int) {
    guard let pos = Position(fen: fen) else { print("  \(name): invalid FEN"); return }
    var nodes = 0
    let secs = timeSeconds { nodes = perft(pos, depth) }
    precondition(nodes == expected,
                 "\(name) perft(\(depth)) = \(nodes), expected \(expected) — MOVE GENERATION BUG")
    let mnps = round1(Double(expected) / secs / 1_000_000)
    print("  perft \(pad(name, 9)) d\(depth): \(expected) nodes in \(round3(secs))s  →  \(mnps) Mnps")
}

// MARK: - App-relevant paths: PGN parse (import / tactics re-parse) + the
// repetition key (game replay / threefold detection).

let operaPGN = """
[Event "Paris"]
[White "Morphy"]
[Black "Allies"]
[Result "1-0"]

1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0
"""

func benchPGNParse(iterations: Int) {
    guard Game().loadPGN(operaPGN) else { print("  loadPGN: PARSE FAILED — skipping"); return }
    var ok = 0
    let secs = timeSeconds {
        for _ in 0..<iterations where Game().loadPGN(operaPGN) { ok += 1 }
    }
    precondition(ok == iterations, "loadPGN failed mid-run")
    print("  loadPGN 17-move game: \(round3(secs / Double(iterations) * 1_000_000)) µs/game (\(iterations)x)")
}

func benchRepetitionKey(iterations: Int) {
    guard let pos = Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1") else { return }
    var sink = 0
    let secs = timeSeconds {
        for _ in 0..<iterations { sink &+= pos.repetitionKey.utf8.count }
    }
    precondition(sink > 0)
    print("  repetitionKey: \(round1(secs / Double(iterations) * 1_000_000_000)) ns/call (\(iterations)x)")
}

#if DEBUG
print("⚠️  DEBUG build — timings are ~100x slow and meaningless. Use: swift run -c release ChessCoreBench\n")
#endif
print("ChessCore perft (move-gen throughput + node-count correctness oracle):")
benchPerft("startpos",
           fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
           depth: 5, expected: 4_865_609)
benchPerft("kiwipete",
           fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
           depth: 4, expected: 4_085_603)
print("\nApp-relevant paths (parse / repetition):")
benchPGNParse(iterations: 20_000)
benchRepetitionKey(iterations: 500_000)
