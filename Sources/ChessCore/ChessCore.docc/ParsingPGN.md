# Parsing PGN

Read multi-game PGN, replay a mainline into board snapshots, and write PGN back
out — including a `Sendable` path that runs off the main actor.

## Overview

ChessCore's PGN support is divided into several cooperating types:

- ``PGNGame`` — one parsed game: ordered tags, the mainline SAN list, the raw
  token stream, and the result.
- ``PGNParser`` — tokenize, parse multi-game text, replay a mainline into a
  `Sendable` snapshot, and parse a single SAN move against a position.
- ``PGNExporter`` — serialize a game's tokens back to movetext.
- ``PGNToken`` — the token alphabet (move / variation / comment / NAG).
- ``PGNDiagnostic`` — structured input issues that lenient parsing cannot
  safely hide.
- ``GameTagCodec`` — an escape-safe `key=value;…` codec for the tag set.
- ``GameTreeSnapshot`` — a versioned, lossless representation of a live tree.

## Parse a PGN string

``PGNParser/parse(_:)`` handles a full multi-game PGN — tag pairs plus
movetext — and returns one ``PGNGame`` per game:

```swift
import ChessCore

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
print(game.moveCount)   // full-move count
print(game.moves)       // ["e4", "e5", "Nf3", "Nc6", "Bb5", ...]
```

Check `game.diagnostics` before importing. For example, a tag roster with no
movetext is returned for inspection with `.tagsOnlyRecord` rather than being
indistinguishable from a deliberately empty game.

A ``PGNGame`` carries its tags in insertion order via ``PGNGame/OrderedTags``,
which keeps the seven-tag roster first:

```swift
for key in game.tags.orderedKeys {
    print(key, "=", game.tags[key] ?? "")
}
```

## Replay a mainline into board snapshots

To follow the game move by move with full positions, replay it into a
``ParsedMainLine`` — a `Sendable` value with a start ``Position`` and an array of
``MainLineMoveSnapshot``:

```swift
let line: ParsedMainLine = PGNParser.parseMainLineSnapshot(from: game)

guard line.diagnostics.isEmpty else {
    // Invalid FEN or SAN fails closed: no partial/desynchronised moves escape.
    return
}

for snap in line.moves {
    print(snap.notation, snap.positionBefore.fen, "->", snap.positionAfter.fen)
    if let annotation = snap.annotation { print("  ", annotation.rawValue) }
    if let eval = snap.engineEval       { print("   eval", eval) }
    if let clk = snap.clockSeconds      { print("   clock", clk) }
}
```

Each ``MainLineMoveSnapshot`` carries the parsed ``Move``, its SAN, the position
before and after, the ``MoveAnnotation`` (from `!?`-style suffixes or NAGs), any
inline comment, and engine eval / best-move / clock data extracted from the
comment.

### Off the main actor

Both ``ParsedMainLine`` and ``MainLineMoveSnapshot`` are `Sendable`, so the
parse can run on a detached task and the result returned to the UI:

```swift
let snapshot = await Task.detached(priority: .userInitiated) {
    PGNParser.mainLineSnapshot(fromMoveText: rawMoveText)
}.value
```

## Materialize a live move tree

``PGNParser/loadGame(from:)`` builds a live ``Game`` and applies the default
whole-tree node budget, including variations. Code that needs a specific budget
and an explicit failure reason can use the throwing overload:

```swift
do {
    let game = try PGNParser.loadGame(from: parsedGame, maximumTreeNodes: 10_000)
    // Use game.
} catch PGNDiagnostic.moveTreeNodeLimitExceeded(let maximumNodes) {
    print("PGN tree exceeds the \(maximumNodes)-node budget")
}
```

## Parse a single move

To turn one SAN token into a ``Move`` against a position — useful when driving
a board directly — use ``PGNParser/parseMove(_:in:)``. It handles
castling (`O-O` / `0-0`), promotion (`=Q`), disambiguation, and captures, and
defaults an ambiguous promotion to a queen:

```swift
var position = Position.initial()
if let move = PGNParser.parseMove("e4", in: position) {
    MoveGenerator.applyMoveUnchecked(&position, move)
}
```

## Write PGN

``PGNExporter/tokenText(from:)`` serializes a game's `moveTokens` (or falls back
to its flat `moves` list) — including `{}` comments and `$n` NAGs:

```swift
let movetext = PGNExporter.tokenText(from: game)
```

## Preserve a live tree losslessly

PGN is the interchange and presentation format. It is not a lossless object
graph for an editing session: comments share one text namespace with embedded
metadata, and deeply hostile variation trees may be bounded during export.
Use ``GameTreeSnapshot`` when a crash-recovery journal or another storage layer
must preserve the authored tree, cursor, node metadata, and ordered tags:

```swift
let snapshot = try GameTreeSnapshot(capturing: liveGame)
let bytes = try JSONEncoder().encode(snapshot)

let decoded = try JSONDecoder().decode(GameTreeSnapshot.self, from: bytes)
let restored = Game()
try restored.restore(from: decoded)

// The restored core model remains fully interoperable with PGN.
let pgn = restored.exportPGN()
```

Snapshot schema 2 stores tags as ordered key/value pairs and preserves the
model's exact insertion order; PGN export still projects the canonical Seven
Tag Roster first. The decoder accepts canonical schema-1 snapshots whose tags
used ``GameTagCodec``, so existing recovery data can be read and rewritten
without making the legacy string encoding the new storage contract. Restore
validates the FEN and replays every UCI move through the legal move generator
before replacing the receiving ``Game``. Decode also bounds node and tag-array
counts before materializing a hostile snapshot.

## Round-trip the tag set

``GameTagCodec`` encodes a full PGN tag set as one escape-safe
`key=value;key=value` string, suitable for persisting a game's tags as a single
value:

```swift
let encoded = GameTagCodec.encode(game.tags)          // "Event=...;White=...;..."
let tags    = GameTagCodec.decodeOrdered(encoded)     // back to OrderedTags
let white   = GameTagCodec.firstValue(forKey: "White", in: encoded)
```

`decode(_:)` returns an unordered `[String: String]` for analytics that don't
care about order; `decodeOrdered(_:)` preserves the original key order for
faithful re-export.
