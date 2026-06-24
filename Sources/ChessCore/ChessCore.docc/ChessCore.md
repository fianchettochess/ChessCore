# ``ChessCore``

A portable, Foundation-only chess core: the position model, legal move
generation, FEN, SAN↔UCI, PGN, an opening book, UCI engine-output parsing, and
the analysis / storage seams — with no Apple-UI dependencies.

## Overview

`ChessCore` is a pure-Swift chess library. It is **Foundation-only**: no
SwiftData, CloudKit, GameKit, CoreML, UIKit, AppKit, SwiftUI, Combine, or
CoreBluetooth, and no networking. Presentation, storage, and engine access sit
behind protocol seams, so the value types are `Sendable` and build everywhere
down to **iOS 13 / macOS 10.15** (and on Linux/Android).

The library is organized in two layers:

- **Primitives** — core chess machinery: ``Position``/``Move``/``Square``,
  ``MoveGenerator`` (+ perft), FEN, ``UCIParser`` (SAN↔UCI), ``PGNParser`` /
  ``PGNExporter``, ``OpeningBook``, ``UCIOutputParser`` / ``StockfishInfo``.
- **Analysis & persistence** — math and seams layered over the model:
  ``AccuracyAggregator``, ``EndgameArchetype``, ``StreakMath``, and the storage
  seam (``JSONBlobStore`` / ``BlobBackedStore``).

The ``ChessEngine`` protocol and ``EngineAnalysis`` types describe an engine
abstraction without binding to any concrete engine — wire up
[SwiftStockfish](https://github.com/jaredbrewer/SwiftStockfish) or a neural engine
behind it.

### A 30-second tour

```swift
import ChessCore

// Start from the initial position and play 1. e4.
var position = Position.initial()
let e4 = UCIParser.uciToMove("e2e4", in: position)!
MoveGenerator.applyMoveUnchecked(&position, e4)

// How many legal replies does Black have?
let replies = MoveGenerator.legalMoves(for: position)   // 20

// Render a move as SAN, and read the FEN back out.
let san = MoveGenerator.algebraicNotation(for: e4, in: .initial())  // "e4"
print(position.fen)  // "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:WorkingWithPositionsAndMoves>
- <doc:ParsingPGN>

### Guides

- <doc:MoveGeneration>
- <doc:FENs>
- <doc:ConvertingMoveNotation>
- <doc:OpeningBookGuide>
- <doc:IntegratingAnEngine>
- <doc:AnalysisMath>
- <doc:StorageSeam>

### The board model

- ``Position``
- ``Square``
- ``Piece``
- ``PieceColor``
- ``PieceType``
- ``Move``
- ``MoveRecord``
- ``CastlingRights``
- ``GameState``
- ``MoveAnnotation``
- ``MoveQuality``

### Move generation & perft

- ``MoveGenerator``

### FEN

- ``Position/init(fen:)``
- ``Position/fen``
- ``Position/positionKey``
- ``Position/stockfishSafeFEN``
- ``Position/capturableEnPassantTarget``
- ``Position/hasInsufficientMaterial``

### SAN ↔ UCI

- ``UCIParser``

### PGN

- ``PGNGame``
- ``PGNParser``
- ``PGNExporter``
- ``PGNToken``
- ``ParsedMainLine``
- ``MainLineMoveSnapshot``
- ``GameTagCodec``

### Opening book

- ``OpeningBook``

### Engine output (UCI)

- ``StockfishInfo``
- ``UCIOutputParser``

### The engine abstraction

- ``ChessEngine``
- ``EngineAnalysis``
- ``GameAnalysis``
- ``PositionEval``
- ``PlayConfig``
- ``GuessEloResult``
- ``EngineError``

### Analysis math

- ``AccuracyAggregator``
- ``EndgameArchetype``
- ``CustomEndgameConfig``
- ``StreakMath``

### The storage seam

- ``JSONBlobStore``
- ``BlobBackedStore``

### Utilities

- ``EvalJSON``
- ``PercentFormat``
