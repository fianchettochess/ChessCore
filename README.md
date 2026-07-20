# ChessCore

[![Swift Package Index — Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffianchettochess%2FChessCore%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/fianchettochess/ChessCore)
[![Swift Package Index — Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffianchettochess%2FChessCore%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/fianchettochess/ChessCore)
[![Release](https://img.shields.io/github/v/release/fianchettochess/ChessCore?sort=semver&label=release&color=blue)](https://github.com/fianchettochess/ChessCore/releases)
[![Linux CI](https://github.com/fianchettochess/ChessCore/actions/workflows/ci-linux.yml/badge.svg)](https://github.com/fianchettochess/ChessCore/actions/workflows/ci-linux.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A portable, Foundation-only Swift chess library: the position model,
perft-verified move generation, FEN, SAN/UCI, PGN, a game tree, and UCI
engine-output parsing. It has no Apple-UI or platform dependencies.

**ChessCore** provides the chess engine and model only. Higher-level analysis,
statistics, and persistence are intended to live in separate packages built on
top of it, keeping the core small, portable, and free of presentation concerns.

## Features

- **Foundation-only.** No SwiftData, CloudKit, GameKit, CoreML, UIKit, AppKit,
  SwiftUI, Combine, CoreBluetooth, or networking. Presentation and engine access
  are defined behind protocol seams, and the value types are `Sendable`.
- **Broad platform support.** A declared deployment target of iOS 13 / macOS
  10.15 (tvOS 13, watchOS 6, visionOS 1) — a hard floor set by the async engine
  seams (Swift-concurrency back-deployment); the pure value types would build
  lower on their own. Cross-compiles for Linux and Android
  (`aarch64-unknown-linux-android28`).
- **Verified correctness.** Magic-bitboard move generation, validated by a perft
  suite with exact node counts (initial `perft(5)` = 4,865,609; Kiwipete
  `perft(4)` = 4,085,603; plus en-passant, promotion, and castling-rights
  positions).

## Contents

| Area | Types |
|---|---|
| Board model | `Position`, `Move`, `Square`, `Piece`, `PieceColor`, `PieceType`, `CastlingRights`, `GameState`, `MoveAnnotation`, `MoveQuality` |
| Move generation | `MoveGenerator` — legal moves, make-move (`applyMoveUnchecked`), check/attack detection, SAN (`algebraicNotation`); perft-verified (suite in `Tests/`, harness in `ChessCoreBench`) |
| Game tree | `Game`, `MoveNode`, `GameTreeSnapshot` |
| FEN | `Position(fen:)`, `Position.fen`, `positionKey`, `stockfishSafeFEN` |
| Notation and PGN | `UCIParser` (SAN/UCI), `PGNParser`, `PGNExporter`, `PGNGame`, `GameTagCodec` |
| Engine interface | `ChessEngine`, `UCIEngine`, `EngineAnalysis`, `UCIOutputParser`, `UCIInfo`, `EngineError` |

The `ChessEngine` and `UCIEngine` protocols and the `EngineAnalysis` types
define an engine interface independent of any concrete engine. Conforming types may wrap
[SwiftStockfish](https://github.com/fianchettochess/SwiftStockfish) or a neural
network engine.

## Installation

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/fianchettochess/ChessCore.git", from: "0.7.1")
```

Then add `"ChessCore"` to the dependencies of any target that uses it.

## Quick start

```swift
import ChessCore

// Begin from the initial position and play 1. e4.
var position = Position.initial()
let e4 = UCIParser.uciToMove("e2e4", in: position)!
MoveGenerator.applyMoveUnchecked(&position, e4)

let replies = MoveGenerator.legalMoves(for: position)               // 20
let san = MoveGenerator.algebraicNotation(for: e4, in: .initial())  // "e4"
print(position.fen)
// rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1
```

`Game` provides a full move tree with variations, navigation, and PGN and FEN
import and export.

## Building and testing

```bash
swift build
swift test
```

The perft suite limits depth in debug builds for fast iteration and runs in full
under the release configuration:

```bash
swift test -c release
```

Cross-compiling for Android from a macOS host requires a Swift toolchain
matching the Swift Android SDK and the NDK's `llvm-ar` as the librarian.

## Documentation

- API reference (DocC): `Sources/ChessCore/ChessCore.docc`. Generate it with
  `swift package generate-documentation --target ChessCore`.
- Guide (Material for MkDocs): `docs-site/`.

## License

ChessCore is available under the MIT license. See [LICENSE](LICENSE).
