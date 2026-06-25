# SAN & UCI

`UCIParser` is pure, engine-agnostic translation between SAN and UCI against a
`Position`. (Stockfish-specific *output* parsing lives in `UCIOutputParser` — see
[Engine protocol](engine-protocol.md).)

## The API

```swift
public enum UCIParser {
    static func uciToMove(_ uci: String, in position: Position) -> Move?
    static func uciToMove(_ uci: String, in legalMoves: [Move]) -> Move?
    static func uciToSAN(_ uci: String, in position: Position) -> String?
    static func sanToUCI(_ san: String, in position: Position) -> String?
    static func convertPVToSAN(_ uciMoves: [String], from position: Position,
                               initialLegalMoves: [Move]? = nil) -> [String]
}
```

## Conversion methods

```swift
let position = Position.initial()

let move = UCIParser.uciToMove("e2e4", in: position)   // Move?
let san  = UCIParser.uciToSAN("e2e4", in: position)    // "e4"
let uci  = UCIParser.sanToUCI("Nf3", in: position)     // "g1f3"
```

`uciToMove` validates the UCI string against the legal moves in the position, so
an illegal or malformed string yields `nil`. If you already have the legal-move
list, the overload that takes `[Move]` skips regeneration:

```swift
let legal = MoveGenerator.legalMoves(for: position)
let move  = UCIParser.uciToMove("e2e4", in: legal)
```

## Converting a principal variation

`convertPVToSAN` replays a UCI PV move-by-move and renders each in SAN. It stops
at the first move it can't parse, so a truncated or illegal line yields the
longest valid prefix:

```swift
let pv = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"]
let sanLine = UCIParser.convertPVToSAN(pv, from: .initial())
// ["e4", "e5", "Nf3", "Nc6", "Bb5"]
```

This is suitable for rendering an engine's `info … pv …` line as human-readable
notation.

## Rendering SAN directly from a Move

If you already hold a `Move`, render it with the move generator instead — it
produces full SAN including disambiguation and check/mate suffixes:

```swift
let san = MoveGenerator.algebraicNotation(for: move, in: position)
```

`UCIParser.uciToSAN` performs the UCI→Move→SAN conversion in a single call.
