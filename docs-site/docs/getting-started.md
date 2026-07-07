# Getting Started

Create a position, generate and apply moves, read the board, and detect game
state.

## Create a position

A `Position` is the complete board state — pieces, side to move, castling rights,
en-passant target, and the halfmove/fullmove counters.

```swift
import ChessCore

let start = Position.initial()              // standard starting position
let empty = Position()                      // empty board, White to move
let custom = Position(fen:                  // any FEN (failable)
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!
```

`init(fen:)` returns `nil` for malformed FEN — it needs at least the four core
fields and eight ranks.

## Generate and apply moves

`MoveGenerator` is a namespace of static functions over a `Position`.

```swift
var position = Position.initial()

// All fully-legal moves (filtered for leaving your own king in check).
let legal = MoveGenerator.legalMoves(for: position)
print(legal.count)   // 20

// Apply one in place. applyMoveUnchecked handles promotion, en passant,
// castling rook moves, the EP target, castling-rights updates, and the
// move counters — it just doesn't re-check legality.
if let e4 = legal.first(where: { $0.uci == "e2e4" }) {
    MoveGenerator.applyMoveUnchecked(&position, e4)
}

print(position.activeColor)   // .black
```

## Read the board

Index a `Position` with a `Square` to get or set a `Piece`:

```swift
let e4 = Square(algebraic: "e4")!
if let piece = position[e4] {
    print(piece.color, piece.type)   // .white .pawn
    print(piece.fenChar)             // "P"
}

print(e4.file, e4.rank)      // 4 3
print(e4.index)              // 28  (rank * 8 + file)
print(e4.algebraic)          // "e4"
print(Square.fromIndex(28))  // the e4 square
```

`Square` coordinates are file/rank `0...7`; `Square.isValid` checks bounds, and
the subscript on `Position` is bounds-safe.

## Detect game state

```swift
let inCheck = MoveGenerator.isInCheck(position)
let hasMove = MoveGenerator.hasAnyLegalMove(for: position)

let state: GameState
switch (inCheck, hasMove) {
case (true,  false): state = .checkmate
case (true,  true):  state = .check
case (false, false): state = .stalemate
default:             state = .playing
}
print(state.isGameOver)

if position.hasInsufficientMaterial {
    print("Draw by insufficient material")   // K v K, K+minor v K, K+B v K+B same color
}
```

## Color and piece helpers

```swift
let side = PieceColor.white
print(side.opposite)         // .black
print(side.persistenceKey)   // "white"  — stable storage key
print(side.shortKey)         // "w"

// Which side did a username play?
let userColor = PieceColor.ofUser(white: "Alice", black: "Bob", username: "bob")  // .black
```

## Next steps

- [The board model](concepts/model.md) — every value type in depth.
- [Move generation & perft](concepts/move-generation.md) — the correctness
  contract.
- [PGN](concepts/pgn.md) — read and write games.
- [The game tree](concepts/game.md) — `Game` and `MoveNode`: navigation,
  variations, annotations, and PGN/FEN I/O.
