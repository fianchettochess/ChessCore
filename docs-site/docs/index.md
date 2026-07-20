# ChessCore

A portable, **Foundation-only** Swift chess core: the position model, legal move
generation (with a perft-verified generator), FEN, SAN↔UCI, PGN, and UCI
engine-output parsing — with no Apple-UI dependencies.

## Features

- **Foundation-only.** No SwiftData, CloudKit, GameKit, CoreML, UIKit, AppKit,
  SwiftUI, Combine, or CoreBluetooth, and no networking. Presentation and engine
  access sit behind protocol seams.
- **Wide reach.** Deployment floor declared at **iOS 13 / macOS 10.15** (tvOS 13,
  watchOS 6, visionOS 1) — a hard floor set by the async engine seams
  (Swift-concurrency back-deployment); the pure value types would build lower on
  their own.
- **Cross-platform.** Builds for `aarch64-unknown-linux-android28`, and the test
  suite runs on macOS and on Linux (on-push CI on ubuntu-latest, `swift:latest`).
  Value types are `Sendable` and presentation-free.
- **Correct.** The move generator is validated by a **perft suite** with exact
  node counts (initial `perft(4) = 197281`, Kiwipete `perft(3) = 97862`, plus
  en-passant and promotion positions).

## Components

The package provides the core chess types: `Position` / `Move` / `Square` /
`Piece`, `MoveGenerator` (with perft), FEN, `UCIParser` (SAN↔UCI), `PGNParser` /
`PGNExporter`, `Game` (the move tree), and `UCIOutputParser` /
`UCIInfo`. The `ChessEngine` protocol and `EngineAnalysis` types describe an
engine abstraction without binding to any concrete engine.

## Example

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
print(position.fen)
// "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
```

## See Also

- [Installation](installation.md) — add ChessCore via Swift Package Manager.
- [Getting Started](getting-started.md) — positions, moves, and game state.
- **Concepts** — one page per major area, starting with
  [the board model](concepts/model.md).
- [Usage Examples](examples.md) — task-oriented code samples.
