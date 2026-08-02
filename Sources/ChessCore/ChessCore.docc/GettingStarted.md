# Getting Started

Add ChessCore to a package, then create a position, generate moves, and apply
one.

## Overview

ChessCore is a Swift Package Manager library. It has no third-party runtime
dependencies — only Foundation — so it builds on every Apple platform from iOS
13 / macOS 10.15 up, as well as on Linux and Android.

## Add the package

In your `Package.swift`:

```swift
// As a remote dependency:
dependencies: [
    .package(url: "https://github.com/fianchettochess/ChessCore.git", .upToNextMinor(from: "0.9.0")),
],
targets: [
    .target(
        name: "MyChessApp",
        dependencies: [
            .product(name: "ChessCore", package: "ChessCore"),
        ]
    ),
]
```

ChessCore is pre-1.0, and under `0.x` the minor is the breaking position.
Prefer `.upToNextMinor(from:)` over `from:` — SwiftPM does not special-case
`0.x`, so `from: "0.9.0"` spans `0.9.0 ..< 1.0.0` and would accept a breaking
`0.10.0`.

Or, for a checkout sitting alongside your project, as a local path dependency:

```swift
dependencies: [
    .package(path: "../ChessCore"),
],
```

Then `import ChessCore` wherever you need it.

## Create a position

A ``Position`` is the complete board state — pieces, side to move, castling
rights, en-passant target, and the halfmove/fullmove counters. Two convenience
entry points:

```swift
import ChessCore

let start = Position.initial()              // standard starting position
let empty = Position()                      // empty board, White to move
let kiwipete = Position(fen:                // any FEN
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!
```

`init(fen:)` is failable: it returns `nil` for malformed FEN (it needs at least
the four core fields and eight ranks).

## Generate and apply moves

``MoveGenerator`` is a namespace of static functions over a ``Position``.

```swift
var position = Position.initial()

// All fully-legal moves (filtered for leaving your own king in check).
let legal = MoveGenerator.legalMoves(for: position)
print(legal.count)   // 20

// Pick one and apply it in place. applyMoveUnchecked handles promotion,
// en passant, castling rook moves, EP target, castling-rights updates,
// and the move counters — it just doesn't re-check legality.
if let e4 = legal.first(where: { $0.uci == "e2e4" }) {
    MoveGenerator.applyMoveUnchecked(&position, e4)
}

print(position.activeColor)   // .black
print(position.fen)
```

## Read the board

Index a ``Position`` with a ``Square`` to read or write a ``Piece``:

```swift
let e4 = Square(algebraic: "e4")!
if let piece = position[e4] {
    print(piece.color, piece.type)   // .white .pawn
    print(piece.fenChar)             // "P"
}

print(e4.file, e4.rank, e4.index, e4.algebraic)   // 4 3 28 "e4"
```

## Detect game state

```swift
if MoveGenerator.isInCheck(position) {
    let hasMove = MoveGenerator.hasAnyLegalMove(for: position)
    let state: GameState = hasMove ? .check : .checkmate
    print(state.isGameOver)
}

if position.hasInsufficientMaterial {
    print("Draw by insufficient material")
}
```

## Next steps

- <doc:WorkingWithPositionsAndMoves> — SAN/UCI notation, perft, FEN safety.
- <doc:ParsingPGN> — read and write PGN, including off-main snapshots.
