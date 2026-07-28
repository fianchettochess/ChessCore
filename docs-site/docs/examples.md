# Usage Examples

The following examples combine ChessCore's components into common tasks. Every
snippet uses only the public API.

## Play a full game from a UCI move list

```swift
import ChessCore

func replay(_ uciMoves: [String]) -> Position {
    var position = Position.initial()
    for uci in uciMoves {
        guard let move = UCIParser.uciToMove(uci, in: position) else { break }
        MoveGenerator.applyMoveUnchecked(&position, move)
    }
    return position
}

let position = replay(["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"])
print(position.fen)
```

## Decide the game result

```swift
func result(of position: Position) -> GameState {
    let inCheck = MoveGenerator.isInCheck(position)
    let hasMove = MoveGenerator.hasAnyLegalMove(for: position)
    switch (inCheck, hasMove) {
    case (true,  false): return .checkmate
    case (false, false): return .stalemate
    case (true,  true):  return .check
    default:
        return position.hasInsufficientMaterial ? .insufficientMaterial : .playing
    }
}
```

## Render a move list as SAN

```swift
func sanMoveList(_ uciMoves: [String]) -> [String] {
    UCIParser.convertPVToSAN(uciMoves, from: .initial())
}

let san = sanMoveList(["e2e4", "e7e5", "g1f3", "b8c6"])
// ["e4", "e5", "Nf3", "Nc6"]
```

## Import a PGN and follow it move by move

```swift
let games = PGNParser.parse(pgnString)
guard let game = games.first else { return }

let line = PGNParser.parseMainLineSnapshot(from: game)
for (i, snap) in line.moves.enumerated() {
    let moveNo = i / 2 + 1
    let dots = i.isMultiple(of: 2) ? "." : "..."
    print("\(moveNo)\(dots) \(snap.notation)")
    if let annotation = snap.annotation { print("   ", annotation.rawValue) }
}
```

## Parse PGN off the main actor

```swift
@MainActor
func importGames(_ pgn: String) async -> [ParsedMainLine] {
    await Task.detached(priority: .userInitiated) {
        PGNParser.parse(pgn).map { PGNParser.parseMainLineSnapshot(from: $0) }
    }.value
}
```

## Build an EngineAnalysis from UCI output

The following engine adapter consumes raw UCI `info` lines (for example, from a
SwiftStockfish stream) and produces an `EngineAnalysis`:

```swift
import ChessCore

func buildAnalysis(
    from infoLines: [String],
    bestMoveLine: String,
    position: Position
) -> EngineAnalysis {
    let legal = MoveGenerator.legalMoves(for: position)

    // Collect the best info per MultiPV index.
    var byPV: [Int: UCIInfo] = [:]
    var depth = 0
    for line in infoLines {
        guard let info = UCIOutputParser.parseInfo(line) else { continue }
        byPV[info.multiPV] = info
        depth = max(depth, info.depth ?? 0)
    }

    let scored: [EngineAnalysis.ScoredMove] = byPV
        .sorted { $0.key < $1.key }
        .compactMap { _, info -> EngineAnalysis.ScoredMove? in
            guard let firstUCI = info.pv.first,
                  let move = UCIParser.uciToMove(firstUCI, in: legal),
                  let score = info.score,
                  let centipawns = info.centipawns else { return nil }
            let notation = MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: legal)
            // Logistic win-probability from centipawns (engine-POV).
            let cp = Double(min(10_000, max(-10_000, centipawns)))
            let probability = 1.0 / (1.0 + exp(-0.00368208 * cp))
            return EngineAnalysis.ScoredMove(
                move: move,
                notation: notation,
                probability: probability,
                score: score,
                pvLine: UCIParser.convertPVToSAN(info.pv, from: position, initialLegalMoves: legal)
            )
        }

    let topScore = byPV[1]?.score
    let evaluation: EngineAnalysis.Evaluation? = topScore.map {
        switch $0 {
        case .cp(let c):   return .centipawns(c)
        case .mate(let m): return .mate(m)
        }
    }
    return EngineAnalysis(topMoves: scored, evaluation: evaluation, depth: depth)
}
```

## Load a position from FEN

A position loaded from a FEN string can be queried directly with ChessCore's move
generation:

```swift
import ChessCore   // Position, MoveGenerator

if let position = Position(fen: someEndgameFEN) {
    let legal = MoveGenerator.legalMoves(for: position)
    print("\(legal.count) legal moves for \(position.activeColor)")
}
```
