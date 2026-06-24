# PGN

ChessCore's PGN support is a few cooperating types: a game model, a parser, a
token-level exporter, and an escape-safe tag codec.

| Type | Role |
|---|---|
| `PGNGame` | one parsed game: ordered tags, mainline SANs, token stream, result |
| `PGNParser` | tokenize, parse multi-game text, replay to a `Sendable` snapshot |
| `PGNExporter` | serialize a game's tokens back to movetext |
| `PGNToken` | the token alphabet (move / variation / comment / NAG) |
| `GameTagCodec` | escape-safe `key=value;…` codec for the tag set |

## Parse a PGN string

`PGNParser.parse(_:)` handles a full multi-game PGN — tags plus movetext — and
returns one `PGNGame` per game:

```swift
let pgn = """
[Event "World Championship"]
[White "Carlsen, Magnus"]
[Black "Nepomniachtchi, Ian"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O 1-0
"""

let games = PGNParser.parse(pgn)
let game = games[0]

print(game.white)       // "Carlsen, Magnus"
print(game.black)       // "Nepomniachtchi, Ian"
print(game.resultText)  // "1-0"
print(game.opening)     // Opening tag, falling back to ECO
print(game.moveCount)   // full-move count
print(game.moves)       // ["e4", "e5", "Nf3", "Nc6", "Bb5", ...]
```

`PGNGame` exposes convenience accessors (`white`, `black`, `date`, `event`,
`resultText`, `opening`, `moveCount`) that default cleanly when a tag is missing.

## Ordered tags

```swift
for key in game.tags.orderedKeys {          // seven-tag roster first, then the rest
    print(key, "=", game.tags[key] ?? "")
}
```

`PGNGame.OrderedTags` preserves insertion order; assigning `nil` removes a key.

## Replay a mainline into board snapshots

To follow a game move by move with full positions, replay it into a
`ParsedMainLine` — a `Sendable` value with a start `Position` and an array of
`MainLineMoveSnapshot`:

```swift
let line: ParsedMainLine = PGNParser.parseMainLineSnapshot(from: game)

for snap in line.moves {
    print(snap.notation,
          snap.positionBefore.fen, "->", snap.positionAfter.fen)
    if let annotation = snap.annotation { print("  ", annotation.rawValue) }
    if let eval = snap.engineEval       { print("   eval", eval) }
    if let best = snap.engineBestMoveUCI { print("   best", best) }
    if let clk = snap.clockSeconds      { print("   clock", clk) }
}
```

Each snapshot carries the parsed `Move`, its SAN, the position before and after,
the `MoveAnnotation` (from `!?`-style suffixes or NAGs), any inline comment, and
engine eval / best-move / clock data extracted from the comment.

### Off the main actor

Both `ParsedMainLine` and `MainLineMoveSnapshot` are `Sendable`, so the heavy
parse can run on a detached task:

```swift
let snapshot = await Task.detached(priority: .userInitiated) {
    PGNParser.mainLineSnapshot(fromMoveText: rawMoveText)
}.value
```

## Parse a single move

```swift
var position = Position.initial()
if let move = PGNParser.parseMove("e4", in: position) {
    MoveGenerator.applyMoveUnchecked(&position, move)
}
```

`parseMove` handles castling (`O-O` / `0-0`), promotion (`=Q`), disambiguation,
and captures, and defaults an ambiguous promotion to a queen.

## Write PGN

```swift
let movetext = PGNExporter.tokenText(from: game)
```

`tokenText(from:)` serializes the game's `moveTokens` (falling back to its flat
`moves` list), including `{}` comments and `$n` NAGs.

## The tag codec

`GameTagCodec` encodes a full PGN tag set as one escape-safe
`key=value;key=value` string — the storage form Fianchetto persists per game:

```swift
let encoded = GameTagCodec.encode(game.tags)              // "Event=...;White=...;..."
let tags    = GameTagCodec.decodeOrdered(encoded)         // back to OrderedTags
let dict    = GameTagCodec.decode(encoded)                // unordered [String: String]
let white   = GameTagCodec.firstValue(forKey: "White", in: encoded)
```

`decodeOrdered` preserves the original key order for faithful re-export;
`decode` returns an unordered dictionary for analytics that don't care.
