# Engine Protocol & UCI Output

ChessCore defines an engine abstraction that is independent of any concrete
engine, and it parses generic UCI `info` and `bestmove` output.

## Parsing UCI output

`UCIOutputParser` converts engine output lines into a structured `UCIInfo`.
The parser conforms to the UCI protocol and does not depend on any
Stockfish-specific behavior.

```swift
public struct UCIInfo: Sendable, Equatable {
    public var depth: Int?
    public var multipv: Int?
    public var scoreCp: Int?
    public var mateIn: Int?
    public var nps: Int?
    public var pv: [String]      // UCI moves

    // Computed API
    public var score: Score         // derived from scoreCp / mateIn
    public var multiPV: Int         // multipv ?? 1
    public var centipawns: Int      // mate maps to ±100_000 (engine-POV)
    public var bestMoveUCI: String? // pv.first
    public var displayText: String  // "+1.3", "M5", "-M3"

    // White-POV conversion
    public func whitePovCentipawns(sideToMoveIsWhite: Bool) -> Int
    public static func whitePovCp(_ cp: Int, sideToMoveIsWhite: Bool) -> Int
    public static func whitePovMate(_ mate: Int, sideToMoveIsWhite: Bool) -> Int

    public enum Score: Sendable, Equatable {
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

// Distil a MultiPV batch — keeps the last (highest-depth) entry per rank.
// The result dictionary maps MultiPV index (1 = best) to the deepest UCIInfo
// seen for that rank; lines without a multipv field count as rank 1.
let byRank: [Int: UCIInfo] = UCIOutputParser.bestInfoByRank(collectedInfos)

// parse(_:) is an alias for parseInfo(_:) used by FianchettoKit call sites:
let info2 = UCIOutputParser.parse(line)
```

!!! note "Bounded scores"
    `parseInfo` returns `nil` for lines carrying `lowerbound` / `upperbound` —
    those are partial results from an unresolved aspiration window and should not
    drive the eval bar or move arrows.

### White-POV scores

UCI engines report scores from the perspective of the side to move. To drive an
eval bar anchored to White you need to flip the sign for Black's lines:

```swift
// Using the instance helper:
let wpCp = info.whitePovCentipawns(sideToMoveIsWhite: position.activeColor == .white)

// Or the static helpers for a raw value you already have:
let flipped = UCIInfo.whitePovCp(rawCp, sideToMoveIsWhite: false)     // Black to move
let mateDist = UCIInfo.whitePovMate(rawMate, sideToMoveIsWhite: false)

// displayText delegates to Score.displayText — the same "+1.3"/"M5" format:
print(info.displayText)
```

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
public struct EngineAnalysis: Sendable {
    public let topMoves: [ScoredMove]
    public let evaluation: Evaluation?
    public let depth: Int?

    public struct ScoredMove: Identifiable, Sendable {
        public var id: String { notation }   // SAN is stable across depth updates
        public let move: Move
        public let notation: String
        public let probability: Double
        public let score: UCIInfo.Score?
        public let pvLine: [String]
    }

    public enum Evaluation: Equatable, Sendable {
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

## Driving a live engine (UCIEngine)

`UCIEngine` is the low-level transport seam. It carries no chess logic — just a
command channel and an ordered output stream. Both `SwiftStockfish.StockfishEngine`
and `SwiftReckless.RecklessEngine` conform to it; the consuming app declares the
conformances (each links its own engine package).

```swift
public protocol UCIEngine: AnyObject, Sendable {
    /// Ordered output lines from the engine, without trailing newlines.
    var output: AsyncStream<String> { get }

    /// Send a raw UCI command (no trailing newline needed).
    func send(_ command: String)

    // Convenience shorthands:
    func uci()       // send("uci")
    func isReady()   // send("isready")
    func quit()      // send("quit")
}
```

A typical adapter loop reads the `output` stream, pipes each line through
`UCIOutputParser.parseInfo` and `UCIOutputParser.parseBestMove`, and accumulates
`UCIInfo` values to later convert into an `EngineAnalysis` via the
`ChessEngine`-level `analyze(position:topK:)` call:

```swift
for await line in engine.output {
    if let info = UCIOutputParser.parseInfo(line) {
        collectedInfos.append(info)
    } else if let bestMove = UCIOutputParser.parseBestMove(line) {
        let byRank = UCIOutputParser.bestInfoByRank(collectedInfos)
        // build EngineAnalysis from byRank …
        break
    }
}
```

!!! note "One engine at a time"
    Some in-process engine implementations (e.g. StockfishEngine) capture
    process-global stdio while live. Only one `UCIEngine` instance should be
    live at a time.

## Wiring a real engine

A typical `ChessEngine` adapter drives [SwiftStockfish](https://github.com/fianchettochess/SwiftStockfish),
sends `position.stockfishSafeFEN`, collects `info` lines via
`UCIOutputParser.parseInfo`, and constructs `ScoredMove` values with
`UCIParser.uciToMove` and `MoveGenerator.algebraicNotation`. See the
[Usage Examples](../examples.md) for a complete implementation.
