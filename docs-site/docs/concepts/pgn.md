# PGN

ChessCore's PGN support consists of several cooperating types: a game model, a
parser, a token-level exporter, and an escape-safe tag codec.

| Type | Role |
|---|---|
| `PGNGame` | one parsed game: ordered tags, mainline SANs, token stream, result |
| `PGNParser` | tokenize, parse multi-game text, replay to a `Sendable` snapshot |
| `PGNExporter` | serialize a game's tokens back to movetext |
| `PGNToken` | the token alphabet (move / variation / comment / NAG) |
| `GameTagCodec` | escape-safe `key=value;…` codec for the tag set |

## Parse a PGN string

`PGNParser.parse(_:)` parses a full multi-game PGN — tags plus movetext — and
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
`resultText`, `opening`, `moveCount`) that return sensible defaults when a tag is
missing.

## Ordered tags

```swift
for key in game.tags.orderedKeys {          // seven-tag roster first, then the rest
    print(key, "=", game.tags[key] ?? "")
}
```

`PGNGame.OrderedTags` preserves insertion order; assigning `nil` removes a key.

## Replay a mainline into board snapshots

To follow a game move by move with full positions, replay it into a
`ParsedMainLine` — a `Sendable` value containing a starting `Position` and an
array of `MainLineMoveSnapshot`:

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
engine evaluation, best-move, and clock data extracted from the comment.

### What a comment yields

`PGNParser.parseEngineComment(_:)` splits a `{ … }` comment into the engine data
it carries and the prose left over. Two vocabularies are understood:

- **The `[%key value]` command syntax the PGN specification reserves.** ChessCore
  reads `[%clk H:MM:SS]` for a clock reading and `[%eval …]` for an evaluation —
  either a signed decimal in pawns (`[%eval -1.42]`) or a mate distance
  (`[%eval #-3]`, reported as `"-M3"`).
- **The dialect `PGNExporter` writes** — an evaluation, then `best <SAN>`, then
  free prose, separated by semicolons: `{+0.34; best Nf3; solid}`. That is this
  library's own format, not a standard, and it round-trips what this library
  exports.

Everything else comes back untouched as prose. An evaluation token must contain
a digit, so the Informant symbols (`+-`, `-+`, `+/-`) survive in a reader's
comment rather than being consumed as evaluations. A `[%eval …]` tag wins over a
bare token in the same comment.

### Off the main actor

Both `ParsedMainLine` and `MainLineMoveSnapshot` are `Sendable`, so a large parse
can run on a detached task:

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

`parseMove` handles castling (`O-O` / `0-0`), promotion (`=Q` and the lenient
`Q` suffix), disambiguation, and captures. A promotion suffix is required;
omitting it does not silently choose a queen.

## Write PGN

```swift
let movetext = PGNExporter.tokenText(from: game)
```

`tokenText(from:)` serializes the game's `moveTokens` (falling back to its flat
`moves` list), including `{}` comments and `$n` NAGs.

## PGN text → live Game → PGN text

The snapshot path above produces an immutable `ParsedMainLine`. For a **live,
mutable game tree** use `PGNParser.loadGame` and `PGNExporter.export` — the
round-trip that bridges PGN text to a `Game` instance and back.

```swift
// Parse PGN text directly into a live Game (first game in the string):
if let game = PGNParser.loadGame(from: pgnString) {
    // game is a fully-hydrated Game with a MoveNode tree,
    // ready for navigation, annotation, and analysis.
    game.undoMove()
    game.setAnnotation(.brilliant, on: game.currentNode!)
}

// If you already have a PGNGame from PGNParser.parse(_:):
if let game = PGNParser.loadGame(from: pgnGame) {
    // SetUp/FEN tags are honored: non-standard start positions work.
}
```

`loadGame(from:)` returns `nil` only when the PGN is syntactically invalid or a
`SetUp`/`FEN` tag contains a malformed FEN string. A valid-but-empty game (no
moves) returns an empty `Game`.

### Export a live Game to PGN

```swift
// Full PGN: seven-tag roster + move text (with variations and annotations):
let pgn = game.exportPGN()

// Export with custom tags:
var tags = PGNGame.OrderedTags()
tags["Event"] = "Club Championship"
tags["White"] = "Alice"
tags["Black"] = "Bob"
let pgn2 = PGNExporter.export(game: game, tags: tags)

// Move text only (no headers) — useful for embedding in a larger document:
let text = PGNExporter.moveText(for: game.rootChildren)
```

`PGNExporter.export` writes variations with `( … )` brackets, annotation
suffixes, and inline comments that include engine eval, best-move, clock time,
and user comments — the same comment format that `loadGame` reads back.

## The tag codec

`GameTagCodec` encodes a full PGN tag set as a single escape-safe
`key=value;key=value` string, suitable for compact per-game storage:

```swift
let encoded = GameTagCodec.encode(game.tags)              // "Event=...;White=...;..."
let tags    = GameTagCodec.decodeOrdered(encoded)         // back to OrderedTags
let dict    = GameTagCodec.decode(encoded)                // unordered [String: String]
let white   = GameTagCodec.firstValue(forKey: "White", in: encoded)
```

`decodeOrdered` preserves the original key order for faithful re-export, while
`decode` returns an unordered dictionary for cases where order is not significant.
