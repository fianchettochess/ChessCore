# FENs

Parse and serialize standard FEN, and select the appropriate one of ChessCore's
three FEN-shaped accessors for a given consumer.

## Overview

A ``Position`` round-trips through standard FEN and exposes three FEN-shaped
accessors — ``Position/fen``, ``Position/positionKey``, and
``Position/stockfishSafeFEN`` — each tuned for a different consumer: display and
storage, cache and transposition keys, and a strict UCI engine, respectively.

## Parsing

```swift
let position = Position(fen:
    "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
```

``Position/init(fen:)`` is failable. It requires at least the four core fields
(placement, side, castling, en passant) and eight ranks, and it recomputes the
king squares. It returns `nil` on malformed input.

## FEN accessors

| Accessor | What it contains | Use for |
|---|---|---|
| ``Position/fen`` | full standard FEN, including the halfmove and fullmove counters | display, storage, round-tripping |
| ``Position/positionKey`` | FEN **without** the move counters (board + side + castling + EP) | the legality / move-cache key, transposition tables |
| ``Position/stockfishSafeFEN`` | sanitized FEN safe for a strict UCI engine | any FEN that crosses into a UCI engine |

```swift
print(position.fen)          // "...b KQkq e3 0 1"
print(position.positionKey)  // "...b KQkq e3"     (no counters)
```

## Sending a FEN to a UCI engine

Stockfish's FEN parser asserts on inconsistent metadata and aborts the process
(`assert(is_ok(s))`). ``Position/stockfishSafeFEN`` zeros out castling rights
that don't match the placement and drops phantom en-passant targets, so it is
always safe to hand to a strict UCI engine.

> Warning: Always send ``Position/stockfishSafeFEN`` — not ``Position/fen`` —
> when a FEN crosses into a UCI engine. A FEN with inconsistent metadata can
> crash Stockfish's parser and take the engine process down with it.

```swift
engine.send("position fen \(position.stockfishSafeFEN)")
engine.send("go depth 20")
```

Use the plain ``Position/fen`` for storage and display.

## Real en passant

``Position/enPassantTarget`` is the raw FEN field.
``Position/capturableEnPassantTarget`` reports the EP square **only when a
capture is genuinely available** — the X-FEN / Polyglot "real en passant" rule.
This is what ``OpeningBook`` uses for transposition matching, because two
positions that differ only in a phantom EP target should be treated as the same
position.

```swift
if let ep = position.capturableEnPassantTarget {
    print("a real en-passant capture is possible on", ep.algebraic)
}
```

## Insufficient material

``Position/hasInsufficientMaterial`` reports the drawn material configurations:

```swift
if position.hasInsufficientMaterial {
    // K vs K, K + single minor vs K, or K+B vs K+B with same-colored bishops
}
```

## See Also

- <doc:MoveGeneration>
- <doc:IntegratingAnEngine>
- ``Position``
