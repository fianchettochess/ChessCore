# Integrating an Engine

Parse generic UCI output into structured data, then wire any engine behind
ChessCore's engine abstraction without binding to a concrete backend.

## Overview

ChessCore describes an engine seam — the ``ChessEngine`` protocol and the
``EngineAnalysis`` result types — without binding to any concrete engine, and it
parses generic UCI `info` / `bestmove` output through ``UCIOutputParser`` into a
structured ``UCIInfo``.

## Parsing UCI output

``UCIOutputParser`` turns engine output lines into a structured ``UCIInfo``.
Despite the name it is generic to the UCI protocol — nothing depends on
Stockfish-specific behavior.

A ``UCIInfo`` carries ``UCIInfo/depth``, an optional ``UCIInfo/Score``,
the ``UCIInfo/pv`` (UCI moves), and ``UCIInfo/multiPV``. A reported
``UCIInfo/Score`` is either centipawns or mate-in-N and exposes display-ready
conversions (`displayText`, `centipawns`, `negated`). Scoreless UCI lines keep
that value absent instead of being misrepresented as an equal evaluation.

```swift
if let info = UCIOutputParser.parseInfo(
    "info depth 20 score cp 31 multipv 1 pv e2e4 e7e5 g1f3"
) {
    if let score = info.score {
        print(info.depth, score.displayText)   // Optional(20)  "+0.3"
    }

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
``EngineAnalysis/ScoredMove`` carries the ``Move``, its SAN notation, an
optional ``UCIInfo/Score``, its PV line, and — for a policy network that
produces one — an optional probability. A search engine leaves the probability
`nil` and ranks by score, so there is no invented value to tell apart from a
genuine zero.

> Note: ``EngineAnalysis/ScoredMove`` is `Identifiable` and its `id` is the SAN
> notation — unique within one position's move list and stable across depth
> updates, so list rows keep a stable identity as the engine publishes deeper
> results.

The ``EngineAnalysis/Evaluation`` enum models a win/draw/loss split, centipawns,
or mate-in-N. It carries the engine's assessment, not a rendering of it —
decimal places, mate spelling, and whether a win/draw/loss split becomes a
percentage are the caller's.

## Errors

``EngineError`` enumerates the failure modes: ``EngineError/engineUnavailable``,
``EngineError/invalidPosition``, ``EngineError/analysisFailed(_:)``, and
``EngineError/noLegalMoves``.

## Wiring a real engine

A typical ``ChessEngine`` adapter drives
[SwiftStockfish](https://github.com/fianchettochess/SwiftStockfish): it sends
``Position/consistentFEN``, collects `info` lines via
``UCIOutputParser/parseInfo(_:)``, and builds each
``EngineAnalysis/ScoredMove`` with ``UCIParser`` and
``MoveGenerator/algebraicNotation(for:in:legalMoves:)``.

> Warning: Always send ``Position/consistentFEN`` — never the raw
> ``Position/fen`` — across the engine boundary. See <doc:FENs>.

## See Also

- <doc:ConvertingMoveNotation>
- <doc:FENs>
- ``ChessEngine``
- ``EngineAnalysis``
- ``UCIOutputParser``
