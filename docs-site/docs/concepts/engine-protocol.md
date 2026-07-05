# Engine Protocol & UCI Output

ChessCore defines an engine abstraction that is independent of any concrete
engine, and it parses generic UCI `info` and `bestmove` output.

## Parsing UCI output

`UCIOutputParser` converts engine output lines into a structured `UCIInfo`.
The parser conforms to the UCI protocol and does not depend on any
Stockfish-specific behavior.

```swift
public struct UCIInfo: Sendable {
    public var depth: Int?
    public var multipv: Int?
    public var scoreCp: Int?
    public var mateIn: Int?
    public var nps: Int?
    public var pv: [String]      // UCI moves

    // Computed API
    public var score: Score         // derived from scoreCp / mateIn
    public var multiPV: Int         // multipv ?? 1
    public var centipawns: Int      // mate maps to ±100_000
    public var bestMoveUCI: String? // pv.first

    public enum Score: Sendable {
        case cp(Int)             // centipawns
        case mate(Int)           // mate in N

        public var centipawns: Int          // mate maps to ±100_000
        public var displayText: String      // "+1.5", "M3", "-M2"
        public var negated: Score
    }
}
```

```swift
if let info = UCIOutputParser.parseInfo(
    "info depth 20 score cp 31 multipv 1 pv e2e4 e7e5 g1f3"
) {
    print(info.depth, info.score.displayText)   // Optional(20)  "+0.3"

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

`ChessEngine` is the abstraction that decouples ChessCore from any specific
engine implementation. Conform a type to it to drive SwiftStockfish, a neural
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
        public let score: UCIInfo.Score?
        public let pvLine: [String]
    }

    public enum Evaluation: Equatable {
        case winDrawLoss(win: Double, draw: Double, loss: Double)
        case centipawns(Int)
        case mate(Int)

        public var displayText: String
        public var scoreText: String
    }
}
```

`ScoredMove.id` is the SAN notation — it is unique within one position's move
list and stable across depth updates, so list rows keep a stable identity as the
engine publishes deeper results.

## Engine errors

```swift
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
`UCIOutputParser.parseInfo`, and constructs `ScoredMove` values with
`UCIParser.uciToMove` and `MoveGenerator.algebraicNotation`. See the
[Usage Examples](../examples.md) for a complete implementation.
