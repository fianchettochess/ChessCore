# Working with Positions and Moves

Translate between SAN and UCI, validate move generation with perft, and cross
the engine boundary safely with FEN.

## Overview

This article builds on <doc:GettingStarted> and covers notation
conversion through ``UCIParser``, the perft-based correctness contract on
``MoveGenerator``, and the FEN accessors that keep a position safe to pass to a
strict UCI engine.

## SAN ↔ UCI conversion

``UCIParser`` performs pure, engine-agnostic translation against a ``Position``.
It supports all four directions:

```swift
let position = Position.initial()

// UCI string → Move (validated against the legal moves in this position).
let move: Move? = UCIParser.uciToMove("e2e4", in: position)

// UCI string → SAN.
let san: String? = UCIParser.uciToSAN("e2e4", in: position)        // "e4"

// SAN → UCI.
let uci: String? = UCIParser.sanToUCI("Nf3", in: position)         // "g1f3"

// A whole principal variation (UCI) → SAN, replayed move by move.
let pv = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"]
let sanLine = UCIParser.convertPVToSAN(pv, from: position)
// ["e4", "e5", "Nf3", "Nc6", "Bb5"]
```

`convertPVToSAN` replays along the line and stops at the first move it cannot
parse, so a truncated or illegal PV yields the longest valid prefix.

When the legal-move list is already available, an overload avoids
regenerating it:

```swift
let legal = MoveGenerator.legalMoves(for: position)
let move = UCIParser.uciToMove("e2e4", in: legal)
```

## Rendering SAN directly

``MoveGenerator/algebraicNotation(for:in:legalMoves:)`` produces full SAN —
disambiguation, capture `x`, promotion `=Q`, and check `+` / mate `#` suffixes:

```swift
let san = MoveGenerator.algebraicNotation(for: move, in: position)

// When the legal moves are already generated, pass them in to avoid
// the work the disambiguator would otherwise repeat:
let legal = MoveGenerator.legalMoves(for: position)
let san2 = MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: legal)
```

## Perft: the move-generation correctness contract

`perft(n)` counts the leaf nodes of the move tree to depth `n`. The exact node
counts for known positions are the standard way to verify a move generator,
and they pin behavior across future implementation changes.

The ChessCore test suite checks these counts. The same walk can be reproduced
with the public API:

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

// "Kiwipete" — the classic edge-case suite (pins, castling, EP, promotion):
let kiwipete = Position(fen:
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!
assert(perft(kiwipete, depth: 3) == 97_862)
```

> Note: ``MoveGenerator/legalMoves(for:)`` caches its result on the position's
> ``Position/positionKey``. Legal moves are fully determined by the position with
> no side effects, so cached values never need invalidation — perft over a
> transposing tree benefits automatically.

## FEN and the engine boundary

A ``Position`` exposes three FEN-shaped accessors, each for a distinct purpose:

- ``Position/fen`` — the full standard FEN, including the halfmove and fullmove
  counters. Use it for display, storage, and round-tripping.
- ``Position/positionKey`` — the FEN *without* the move counters (board + side +
  castling + EP). This is the legality/cache key and the right key for
  transposition tables.
- ``Position/stockfishSafeFEN`` — a sanitized FEN for handing to a strict UCI
  engine. Stockfish's parser asserts on inconsistent metadata and aborts the
  process; this accessor zeros out castling rights that don't match the piece
  placement and drops phantom en-passant targets.

```swift
// ALWAYS use stockfishSafeFEN when a FEN crosses into a UCI engine:
engine.send("position fen \(position.stockfishSafeFEN)")
engine.send("go depth 20")

// Use the plain fen for storage / display:
store.save(position.fen)
```

The related ``Position/capturableEnPassantTarget`` reports the en passant square
*only when a capture is actually available* (the X-FEN / Polyglot "real en
passant" rule), which is the correct key for transposition matching.

## Annotating moves

``MoveAnnotation`` models the PGN/NAG glyphs (`!!`, `!`, `?`, `??`, …)
independently of presentation. It reads NAG codes and strips suffix glyphs from
a SAN string:

```swift
let (cleaned, annotation) = MoveAnnotation.extract(from: "Nf3!?")
// cleaned == "Nf3", annotation == .interesting

let fromNag = MoveAnnotation.from(nag: 1)        // .good
print(MoveAnnotation.brilliant.pgnSuffix ?? "")  // the PGN suffix glyph
```
