# Integrating an Engine

Parse generic UCI output into structured data, then wire any engine behind
ChessCore's engine abstraction without binding to a concrete backend.

## Overview

ChessCore describes an engine seam — the ``ChessEngine`` protocol and the
``EngineAnalysis`` result types — without binding to any concrete engine, and it
parses generic UCI `info` / `bestmove` output through ``UCIOutputParser`` into a
structured ``StockfishInfo``.

## Parsing UCI output

``UCIOutputParser`` turns engine output lines into a structured ``StockfishInfo``.
Despite the name it is generic to the UCI protocol — nothing depends on
Stockfish-specific behavior.

A ``StockfishInfo`` carries ``StockfishInfo/depth``, a ``StockfishInfo/Score``,
the ``StockfishInfo/pv`` (UCI moves), and ``StockfishInfo/multiPV``. The
``StockfishInfo/Score`` is either centipawns or mate-in-N and exposes
display-ready conversions (`displayText`, `winProbability`, `whiteWinProbability`,
`negated`).

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

> Note: ``UCIOutputParser/parseInfo(_:)`` returns `nil` for lines carrying
> `lowerbound` / `upperbound` — those are partial results from an unresolved
> aspiration window and should not drive the eval bar or move arrows.

## The ChessEngine protocol

``ChessEngine`` is the engine seam — implement it over SwiftStockfish, a neural
engine, or a mock. It exposes a name, a readiness flag, and a single async
``ChessEngine/analyze(position:topK:)`` entry point that returns an
``EngineAnalysis``:

```swift
public protocol ChessEngine: AnyObject {
    var name: String { get }
    var isReady: Bool { get }
    func analyze(position: Position, topK: Int) async throws -> EngineAnalysis
}
```

## EngineAnalysis

An ``EngineAnalysis`` holds the ranked ``EngineAnalysis/ScoredMove`` list, an
optional ``EngineAnalysis/Evaluation``, and the search depth. Each
``EngineAnalysis/ScoredMove`` carries the ``Move``, its SAN notation, a
probability, an optional ``StockfishInfo/Score``, and its PV line.

> Note: ``EngineAnalysis/ScoredMove`` is `Identifiable` and its `id` is the SAN
> notation — unique within one position's move list and stable across depth
> updates, so list rows keep a stable identity as the engine publishes deeper
> results.

The ``EngineAnalysis/Evaluation`` enum models a win/draw/loss split, centipawns,
or mate-in-N, and renders display text plus the same logistic
`whiteWinProbability` used elsewhere in ChessCore.

## Game-level analysis types

``GameAnalysis`` aggregates per-move results into accuracy figures, where each
``GameAnalysis/MoveResult`` records the move index and the rank / probability of
the player's move. ``PositionEval`` captures the best move and the
per-MultiPV ``StockfishInfo/Score`` map for a single position, and
``GuessEloResult`` carries an estimated Elo per side.

## Play configuration and errors

``PlayConfig`` selects which engine to play against
(``PlayConfig/Engine``) and which color the human takes
(``PlayConfig/PlayerColor``). ``EngineError`` enumerates the failure modes —
model-not-loaded, invalid input, prediction failure, and no-legal-moves.

## Wiring a real engine

A typical ``ChessEngine`` adapter drives
[SwiftStockfish](https://github.com/jaredbrewer/SwiftStockfish): it sends
``Position/stockfishSafeFEN``, collects `info` lines via
``UCIOutputParser/parseInfo(_:)``, and builds each
``EngineAnalysis/ScoredMove`` with ``UCIParser`` and
``MoveGenerator/algebraicNotation(for:in:legalMoves:)``.

> Warning: Always send ``Position/stockfishSafeFEN`` — never the raw
> ``Position/fen`` — across the engine boundary. See <doc:FENs>.

## See Also

- <doc:ConvertingMoveNotation>
- <doc:FENs>
- <doc:AnalysisMath>
- ``ChessEngine``
- ``EngineAnalysis``
- ``UCIOutputParser``
