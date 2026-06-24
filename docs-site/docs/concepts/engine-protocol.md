# Engine Protocol & UCI Output

ChessCore describes an engine abstraction without binding to a concrete engine,
and it parses generic UCI `info` / `bestmove` output.

## Parsing UCI output

`UCIOutputParser` turns engine output lines into a structured `StockfishInfo`.
Despite the name it's generic to the UCI protocol — nothing depends on
Stockfish-specific behavior.

```swift
public struct StockfishInfo: Sendable {
    public var depth: Int
    public var score: Score
    public var pv: [String]      // UCI moves
    public var multiPV: Int

    public enum Score: Sendable {
        case cp(Int)             // centipawns
        case mate(Int)           // mate in N

        public var centipawns: Int          // mate maps to +/- 100_000
        public var displayText: String      // "+1.5", "M3", "-M2"
        public var winProbability: Double   // logistic 1/(1+exp(-0.00368208 * cp))
        public var whiteWinProbability: Double
        public var negated: Score
    }
}
```

```swift
if let info = UCIOutputParser.parseInfo(
    "info depth 20 score cp 31 multipv 1 pv e2e4 e7e5 g1f3"
) {
    print(info.depth, info.score.displayText)   // 20  "+0.31"
    print(info.score.winProbability)            // ~0.53

    // Render the PV in SAN:
    let san = UCIParser.convertPVToSAN(info.pv, from: position)
}

let best = UCIOutputParser.parseBestMove("bestmove e2e4 ponder e7e5")   // "e2e4"
```

!!! note "Bounded scores"
    `parseInfo` returns `nil` for lines carrying `lowerbound` / `upperbound` —
    those are partial results from an unresolved aspiration window and should not
    drive the eval bar or move arrows.

## The ChessEngine protocol

`ChessEngine` is the engine seam — implement it over SwiftStockfish, a neural
engine, or a mock:

```swift
public protocol ChessEngine: AnyObject {
    var name: String { get }
    var isReady: Bool { get }
    func analyze(position: Position, topK: Int) async throws -> EngineAnalysis
}
```

## EngineAnalysis

```swift
public struct EngineAnalysis {
    public let topMoves: [ScoredMove]
    public let evaluation: Evaluation?
    public let depth: Int?

    public struct ScoredMove: Identifiable {
        public var id: String { notation }   // SAN is stable across depth updates
        public let move: Move
        public let notation: String
        public let probability: Double
        public let score: StockfishInfo.Score?
        public let pvLine: [String]
    }

    public enum Evaluation: Equatable {
        case winDrawLoss(win: Double, draw: Double, loss: Double)
        case centipawns(Int)
        case mate(Int)

        public var displayText: String
        public var whiteWinProbability: Double   // same 0.00368208 logistic
        public var scoreText: String
    }
}
```

`ScoredMove.id` is the SAN notation — it is unique within one position's move
list and stable across depth updates, so list rows keep a stable identity as the
engine publishes deeper results.

## Game-level analysis types

```swift
public struct GameAnalysis {
    public let moveResults: [MoveResult]
    public var accuracy: Double        // fraction with playerMoveRank == 0
    public var top3Accuracy: Double    // fraction with rank in 0..<3
    public var averageProbability: Double

    public struct MoveResult {
        public let moveIndex: Int
        public let playerMoveRank: Int
        public let playerMoveProbability: Double
    }
}

public struct PositionEval {
    public let bestMoveUCI: String
    public let scores: [Int: StockfishInfo.Score]   // keyed by MultiPV index
    public var bestScore: StockfishInfo.Score
    public var secondBestScore: StockfishInfo.Score?
}

public struct GuessEloResult {
    public let whiteElo: Int?
    public let blackElo: Int?
}
```

## Play configuration and errors

```swift
public struct PlayConfig: Equatable {
    public var engine: Engine          // .maia | .stockfish
    public var playerColor: PlayerColor // .white | .black
    public enum Engine: String, CaseIterable { case maia = "Maia", stockfish = "Stockfish" }
    public enum PlayerColor: String, CaseIterable { case white = "White", black = "Black" }
}

public enum EngineError: LocalizedError {
    case modelNotLoaded
    case invalidInput
    case predictionFailed(String)
    case noLegalMoves
}
```

## Wiring a real engine

A typical `ChessEngine` adapter drives [SwiftStockfish](https://github.com/jaredbrewer/SwiftStockfish),
sends `position.stockfishSafeFEN`, collects `info` lines via
`UCIOutputParser.parseInfo`, and builds `ScoredMove`s with
`UCIParser.uciToMove` / `MoveGenerator.algebraicNotation`. See the
[Usage Examples](../examples.md) for a sketch.
