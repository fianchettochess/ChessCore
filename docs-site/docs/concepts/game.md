# The Game Tree

`Game` is ChessCore's mutable, navigable game model — the move tree, the current
position, game state, and PGN/FEN I/O in one class. `MoveNode` is a single node
in that tree: the move played, the position before it, its children (main line
first, then variations), and per-node annotations and engine metadata.

Together they are the headline "Game tree" area listed in the package README, and
the entry point for any board UI, repertoire tool, or analysis surface built on
ChessCore.

## Game

```swift
public final class Game {
    // Current state
    public private(set) var position: Position
    public private(set) var startPosition: Position
    public private(set) var currentNode: MoveNode?

    // Tree
    public var rootChildren: [MoveNode]
    public var legalMoves: [Move]          // cached per position
    public var lastMove: Move?             // currentNode?.move
    public var mainLine: [MoveNode]        // flat sequence from root
    public var moveHistory: [MoveRecord]   // mainLine as MoveRecords
    public var currentMoveIndex: Int       // -1 at start, 0-based from root
    public var gameState: GameState        // cached per position+node

    // Change counters (for cache invalidation in UI layers)
    public private(set) var treeMutationCount: Int
    public private(set) var nodePropertyVersion: Int

    // Undo/redo state
    public var canUndo: Bool
    public var canRedo: Bool

    // Tags from the last loaded PGN (used by exportPGN)
    public var loadedTags: PGNGame.OrderedTags?
}
```

`Game` is a pure domain object — no SwiftUI, no SwiftData, no observation
framework, and no interaction state (no selected square, no pending promotion).
Those belong to whatever drives it, so a consumer is free to layer an observable
wrapper, a clock, or sound and haptic side-effects over `apply(_:)` without
fighting the model for ownership.

### Navigation

```swift
let game = Game()

// Cursor movement — never mutates the tree, only `position` / `currentNode`.
game.undoMove()                        // step back one ply
game.redoMove()                        // step forward along the main continuation
game.navigateToNode(someNode)          // jump directly to any node
game.navigateToStart()                 // return to startPosition

// canUndo / canRedo gate UI controls:
if game.canRedo { game.redoMove() }

// currentMoveIndex is -1 at start, then the 0-based ply of the current node:
print(game.currentMoveIndex)
```

### Applying moves

```swift
// Apply a pre-validated Move (promotion already resolved).
// Updates the tree and the position, and nothing else — a clock, a sound, or
// a haptic belongs to whatever is driving the game.
game.apply(move)

// Apply a move loaded from PGN. If the identical move already exists
// among the siblings, the cursor moves to it (no duplicate node created).
game.applyMoveFromPGN(move)
```

### Mutation — new game, reset, retract

```swift
game.newGame()              // clear tree, reset to initial position
_ = game.loadFEN(fenString) // reset to any position; returns false on bad FEN
game.retractLastPlies(2)    // physically remove the last 2 plies from the tree
                            // (unlike undoMove, retract deletes the nodes)
```

`retractLastPlies` is the right call for a physical take-back on a sensing board:
it deletes the nodes so the next move played becomes the main line rather than a
variation.

### Variations

```swift
// Promote a variation so it becomes the main continuation.
game.promoteVariation(node)

// Delete a node and its entire subtree.
game.deleteFromNode(node)
```

### Annotations

All annotation calls write to `MoveNode` fields and bump `nodePropertyVersion`
so UI layers know to re-render node-detail views without a full tree diff:

```swift
game.setAnnotation(.brilliant, on: node)        // MoveAnnotation?
game.setComment("Good practical choice", on: node)
game.clearComment(on: node)
game.setEngineResults(on: node, bestMoveUCI: "e2e4", eval: "+0.3")
game.setMoveQuality(.excellent, accuracy: 97.4, on: node)

// After a batch of writes straight to MoveNode fields, coalesce the
// invalidation into a single bump:
game.bumpNodeProperty()
```

### Change counters

`Game` exposes two monotonic counters that UI caches key off:

| Counter | When it increments |
|---|---|
| `treeMutationCount` | tree structure changes: new move, promote/delete variation, `loadPGN`, `newGame` |
| `nodePropertyVersion` | node-field writes: annotation, comment, engine results, quality — without structural change |

Navigation (`undoMove`, `navigateToNode`, …) bumps neither counter.

### Reconciliation

`reconcile(toPlacementOf:maxPly:)` catches up the game tree to an external
position without discarding history — useful when a sensing board or remote game
feed skips ahead by one or two moves:

```swift
// Returns true and applies the moves through the tree if reachable within maxPly.
// Returns false with no mutation if it cannot reconcile.
let ok = game.reconcile(toPlacementOf: targetPosition, maxPly: 4)

// Query-only variant — returns the move sequence without applying it:
if let path = game.reconcilePath(toPlacementOf: target, maxPly: 4) {
    for m in path { myAdapter.apply(m) }   // apply with custom side-effects
}
```

Matching is on piece placement + side-to-move (the observable board state). The
resulting tree position has fully consistent castling rights and en-passant state
regardless of the target FEN's metadata fields.

### PGN and FEN I/O

The `Game`-level I/O methods delegate to `PGNParser` and `PGNExporter` (see
[PGN](pgn.md) for the full round-trip):

```swift
// Load: returns true on success, false if the PGN is invalid.
_ = game.loadPGN(pgnString)           // first game in the string
_ = game.loadPGNGame(pgnGame)         // from a PGNGame you already have

// Export: emits seven-tag roster + full move text with variations.
let pgn = game.exportPGN()
```

`loadedTags` is populated on `loadPGNGame` and used by `exportPGN` to
round-trip the original headers. Assign `nil` to clear them (exportPGN will
fall back to neutral placeholder tags).

---

## MoveNode

`MoveNode` is a plain reference type with no observation-framework dependency,
so it remains portable across Apple, Linux, and Android consumers. App layers
can wrap it with `@Observable`.

```swift
public final class MoveNode: Identifiable {
    public var id: UUID { get }                  // generated lazily, then stable
    public let move: Move
    public let notation: String               // SAN
    public let positionBefore: Position
    public var children: [MoveNode]           // mainline first, then variations
    public weak var parent: MoveNode?
    public var plyIndex: Int                  // zero-based, relative to this tree

    // Per-node data
    public var annotation: MoveAnnotation?
    public var comment: String?
    public var engineBestMoveUCI: String?
    public var engineEval: String?            // e.g. "+0.3"
    public var moveQuality: MoveQuality?
    public var moveAccuracy: Double?
    public var clockSeconds: TimeInterval?
}
```

### Computed members

```swift
node.moveNumber          // positionBefore.fullmoveNumber
node.moverColor          // positionBefore.activeColor

// positionAfter is lazily computed and cached on first access:
node.positionAfter       // position after applying node.move

// Tree structure helpers:
node.mainContinuation    // children.first — the main reply
node.variations          // children.dropFirst() — all non-main children
node.hasVariations       // children.count > 1

node.isOnMainLine        // true when every ancestor is also its parent's first child
node.pathFromRoot()      // [MoveNode] from the root to this node (inclusive)
```

### Walking the tree

```swift
// Walk the main line from the root:
var node = game.rootChildren.first
while let n = node {
    print(n.moveNumber, n.notation)
    node = n.mainContinuation
}

// Or use the computed property — already the flat main line:
for n in game.mainLine {
    print(n.notation)
}

// pathFromRoot traces back to the root — useful to reconstruct the
// position sequence for any node, including variation nodes:
let path = someVariationNode.pathFromRoot()
```

### PGN metadata

A loaded game's tags are readable as typed values rather than raw strings:

```swift
game.playerName(for: .white)   // String?  — the `White` tag, as written
game.elo(for: .black)          // Int?     — `BlackElo`, nil for "?" / "0" / absent
game.initialClockSeconds       // TimeInterval? — base time from `TimeControl`

game.hasClockAnnotations       // Bool — does the game carry {[%clk ...]} values?
game.clockTimes                // (white: TimeInterval?, black: TimeInterval?, active: PieceColor)
```

`clockTimes` reconstructs both sides' clocks at the currently selected node from
the `[%clk]` annotations along the path from the root, falling back to
`initialClockSeconds` before a side's first annotated move.

`initialClockSeconds` covers the `TimeControl` forms the PGN specification
defines: sudden death (`600`), increment (`300+5`), moves-per-period
(`40/5400`), hourglass (`*180`), and multi-period (`40/5400:1800:*60`, whose
first period is where the clock starts). `-` and `?` yield `nil`.

---

## PGN ↔ live Game bridge

The bridge between PGN text and a live `Game` tree is in `PGNParser` and
`PGNExporter`. See [PGN — PGN text → live Game → PGN text](pgn.md#pgn-text-live-game-pgn-text)
for a full walkthrough. The key entry points:

| Function | Description |
|---|---|
| `PGNParser.loadGame(from: String) -> Game?` | Parse PGN text; return first game as a live `Game` |
| `PGNParser.loadGame(from: PGNGame) -> Game?` | Build a live `Game` from a `PGNGame` you already parsed |
| `PGNExporter.export(game: Game, tags:) -> String` | Full PGN with headers + move text |
| `PGNExporter.moveText(for: [MoveNode]) -> String` | Move text only (no headers) |
| `Game.exportPGN() -> String` | Convenience wrapper for `PGNExporter.export` |
| `Game.loadPGN(_ pgn: String) -> Bool` | Load into the receiver in-place |
| `Game.loadPGNGame(_ pgnGame: PGNGame) -> Bool` | Load from a `PGNGame` in-place |

`SetUp`/`FEN` tags are honored: a PGN that starts from a non-initial position
will seed the `Game` from the tag's FEN before replaying moves.
