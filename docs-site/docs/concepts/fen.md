# FEN

ChessCore parses and serializes standard FEN, and exposes three FEN-shaped
accessors, each suited to a different purpose.

## Parsing

```swift
let position = Position(fen:
    "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
```

`init(fen:)` is failable. It requires at least the four core fields
(placement, side, castling, en-passant) and eight ranks, and it recomputes the
king squares. It returns `nil` on malformed input.

## The three accessors

| Accessor | What it contains | Use for |
|---|---|---|
| `fen` | full standard FEN, including the halfmove and fullmove counters | display, storage, round-tripping |
| `positionKey` | FEN **without** the move counters (board + side + castling + EP) | the legality / transposition key |
| `consistentFEN` | metadata fields made consistent with the placement | any FEN leaving for a parser you don't control |

```swift
print(position.fen)          // "...b KQkq e3 0 1"
print(position.positionKey)  // "...b KQkq e3"     (no counters)
```

## Crossing the engine boundary

Stockfish's FEN parser asserts on inconsistent metadata and **aborts the
process** (`assert(is_ok(s))`). Always hand it `consistentFEN`, which zeros out
castling rights that don't match the placement and drops phantom en-passant
targets:

```swift
engine.send("position fen \(position.consistentFEN)")
engine.send("go depth 20")
```

## Real en passant

`enPassantTarget` is the raw FEN field. `capturableEnPassantTarget` reports the EP
square **only when a capture is genuinely available** — the X-FEN / Polyglot
"real en passant" rule. Use it for transposition matching, since two positions
that differ only in a phantom EP target should be treated as the same position.

```swift
if let ep = position.capturableEnPassantTarget {
    print("a real en-passant capture is possible on", ep.algebraic)
}
```

## Insufficient material

```swift
if position.hasInsufficientMaterial {
    // K vs K, K + single minor vs K, or K+B vs K+B with same-colored bishops
}
```
