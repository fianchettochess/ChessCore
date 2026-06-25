# Converting Move Notation

Translate between SAN and UCI against a position, and render an engine's
principal variation as human-readable notation.

## Overview

``UCIParser`` is pure, engine-agnostic translation between SAN and UCI against a
``Position``. It covers all four directions plus principal-variation conversion.

> Note: Stockfish-specific *output* parsing (turning `info` / `bestmove` lines
> into structured data) lives in ``UCIOutputParser`` — see
> <doc:IntegratingAnEngine>. ``UCIParser`` is only about move-notation
> translation.

## Translating between SAN and UCI

```swift
let position = Position.initial()

let move = UCIParser.uciToMove("e2e4", in: position)   // Move?
let san  = UCIParser.uciToSAN("e2e4", in: position)    // "e4"
let uci  = UCIParser.sanToUCI("Nf3", in: position)     // "g1f3"
```

``UCIParser`` validates the UCI string against the legal moves in the position,
so an illegal or malformed string yields `nil`. If you already have the
legal-move list, the overload that takes `[Move]` skips regeneration:

```swift
let legal = MoveGenerator.legalMoves(for: position)
let move  = UCIParser.uciToMove("e2e4", in: legal)
```

``UCIParser/uciToSAN(_:in:)`` is the convenience that does the UCI → ``Move`` →
SAN chain for you, and ``UCIParser/sanToUCI(_:in:)`` goes the other way.

## Converting a principal variation

``UCIParser/convertPVToSAN(_:from:initialLegalMoves:)`` replays a UCI PV
move-by-move and renders each in SAN. It stops at the first move it can't parse,
so a truncated or illegal line yields the longest valid prefix:

```swift
let pv = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"]
let sanLine = UCIParser.convertPVToSAN(pv, from: .initial())
// ["e4", "e5", "Nf3", "Nc6", "Bb5"]
```

Use this to render an engine's `info … pv …` line as human-readable notation.

## Rendering SAN directly from a Move

If you already hold a ``Move``, render it with the move generator instead — it
produces full SAN including disambiguation and check/mate suffixes:

```swift
let san = MoveGenerator.algebraicNotation(for: move, in: position)
```

``UCIParser/uciToSAN(_:in:)`` is the convenience that does the UCI → ``Move`` →
SAN chain when you start from a UCI string rather than a ``Move``.

## See Also

- <doc:MoveGeneration>
- <doc:IntegratingAnEngine>
- ``UCIParser``
- ``MoveGenerator``
