# Move Generation & Perft

`MoveGenerator` is a namespace of static functions over a `Position`: legal move
generation, move application, SAN notation, and attack detection — all validated
by a perft suite.

## The API

```swift
public enum MoveGenerator {
    static func legalMoves(for position: Position) -> [Move]
    static func findLegalMoves(for position: Position, piece: PieceType, to target: Square) -> [Move]
    static func hasAnyLegalMove(for position: Position) -> Bool
    static func isInCheck(_ position: Position) -> Bool
    static func applyMoveUnchecked(_ position: inout Position, _ move: Move)
    static func algebraicNotation(for move: Move, in position: Position, legalMoves: [Move]? = nil) -> String
    static func findKing(in position: Position, color: PieceColor) -> Square
    static func isSquareAttacked(_ square: Square, by color: PieceColor, in position: Position) -> Bool
}
```

## Legal moves

`legalMoves(for:)` returns the fully-legal moves — pseudo-legal moves filtered to
exclude any that leave the mover's own king in check.

```swift
let legal = MoveGenerator.legalMoves(for: .initial())   // 20 moves
```

The result is **cached** on the position's `positionKey`. Legal moves are fully
determined by the position with no side effects, so cached values never need
invalidation — repeated lookups and transposing trees benefit automatically. The
cache is thread-safe.

To narrow generation — for SAN disambiguation or parsing a PGN move — use
`findLegalMoves(for:piece:to:)`:

```swift
// Which knight moves can reach f3?
let toF3 = MoveGenerator.findLegalMoves(for: position, piece: .knight, to: Square(algebraic: "f3")!)
```

## Applying a move

`applyMoveUnchecked(_:_:)` mutates a `Position` in place and handles every
special case:

- promotion (replaces the pawn with the promotion piece)
- en passant (removes the captured pawn)
- castling (moves the rook too)
- sets / clears the en-passant target
- updates castling rights when a king or rook moves
- advances the halfmove clock and fullmove counter
- flips the side to move

It does **not** check legality — pass it a move you generated, or one you
validated with `UCIParser`.

```swift
var position = Position.initial()
let e4 = MoveGenerator.legalMoves(for: position).first { $0.uci == "e2e4" }!
MoveGenerator.applyMoveUnchecked(&position, e4)
```

## Check, mate, stalemate

```swift
let inCheck = MoveGenerator.isInCheck(position)
let canMove = MoveGenerator.hasAnyLegalMove(for: position)
// checkmate == inCheck && !canMove ; stalemate == !inCheck && !canMove

let king = MoveGenerator.findKing(in: position, color: .white)
let attacked = MoveGenerator.isSquareAttacked(king, by: .black, in: position)
```

## SAN notation

`algebraicNotation(for:in:)` produces full SAN: disambiguation, capture `x`,
promotion `=Q`, and check `+` / mate `#` suffixes.

```swift
let san = MoveGenerator.algebraicNotation(for: e4, in: .initial())   // "e4"

// If you already have the legal moves, pass them to skip recomputation:
let legal = MoveGenerator.legalMoves(for: position)
let san2 = MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: legal)
```

## Perft: the correctness contract

`perft(n)` counts the leaf nodes of the move tree to depth `n`. Matching the
known exact counts for standard positions is how a move generator is proven
correct — and these counts pin behavior for any future magic-bitboard rewrite.

ChessCore's own test suite checks these; you can reproduce the walk with the
public API:

```swift
func perft(_ position: Position, depth: Int) -> Int {
    if depth == 0 { return 1 }
    let moves = MoveGenerator.legalMoves(for: position)
    if depth == 1 { return moves.count }
    var nodes = 0
    for move in moves {
        var next = position
        MoveGenerator.applyMoveUnchecked(&next, move)
        nodes += perft(next, depth: depth - 1)
    }
    return nodes
}

let start = Position.initial()
assert(perft(start, depth: 1) == 20)
assert(perft(start, depth: 2) == 400)
assert(perft(start, depth: 3) == 8902)
assert(perft(start, depth: 4) == 197_281)

// "Kiwipete" — pins, castling, en passant, promotion all in one position:
let kiwipete = Position(fen:
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!
assert(perft(kiwipete, depth: 3) == 97_862)
```
