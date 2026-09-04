# Changelog

All notable changes to ChessCore are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
ChessCore is pre-1.0: **under `0.x` the minor is the breaking position**, so
`0.8.0 → 0.9.0` may break source compatibility and `0.7.1 → 0.7.2` may not.
Depend on it with `.upToNextMinor(from:)` rather than `from:` — SwiftPM does not
special-case `0.x`, so `from: "0.9.0"` spans `0.9.0 ..< 1.0.0` and would accept a
breaking `0.10.0`.

Published tags are never moved or re-cut.

## [0.11.0] — 2026-09-03

Breaking. Phase 2 of the `PieceColor`/`PieceType` serialization migration —
phase 1 (0.10.3) taught the decoder to read the string form ahead of anything
writing it; this flips the encoder to write it.

### Changed

- **`PieceColor` and `PieceType` now encode as a bare string** —
  `PieceColor.white` writes `"white"`, `PieceType.knight` writes `"knight"` —
  matching `persistenceKey`, instead of the keyed container synthesized
  `Codable` used to produce (`{"white":{}}`, `{"knight":{}}`). A `Piece`
  encodes accordingly: `{"color":"white","type":"knight"}` rather than
  `{"color":{"white":{}},"type":{"knight":{}}}`.

  The decoder is unchanged and unaffected: it has accepted both forms since
  0.10.3 and keeps doing so, so blobs written before this release still load.
  Only the shape of newly-written blobs changes. Nothing else in this package
  persists a `PieceColor` or `PieceType` outside `persistenceKey`/`Codable`,
  so no other symbol moves.

## [0.9.1] — 2026-08-19

Additive. No source-compatibility change.

### Added

- `Position.hasMatingMaterial(for:)` — whether ONE named side retains material
  that could deliver mate.

  This is not the question `hasInsufficientMaterial` answers. That property asks
  whether NEITHER side can mate (a dead position) and therefore returns `false`
  as soon as any pawn, rook or queen is on the board, whichever colour owns it.
  A flag fall needs the per-colour question: FIDE 6.9 draws the game when the
  player who did NOT run out of time cannot checkmate. Without this, a player
  holding a bare king is awarded the win when the opponent's clock expires —
  and because a queen on the board makes the position "not dead", the bilateral
  property never intervenes.

  **Which definition.** FIDE 6.9 says the opponent must be unable to mate "by
  any possible series of legal moves", and *any* series includes the flagged
  player cooperating — so the literal test is whether a helpmate exists, under
  which K+N against K+P is a win on time. This implements the common convention
  instead (Lichess, chess.com, most engines): judge the would-be winner's
  material alone. That choice is deliberate and documented on the property; a
  reader comparing it with the rulebook will find it diverges, and that
  divergence is the decision rather than a defect.

## [0.9.0] — 2026-08-01

Breaking. A pre-publication pass over the public surface, removing symbols that
named product concepts rather than chess ones. Entries below give the
replacement to write.

### Removed

- **`Game.restoreDrillSnapshot(_:)`.** The body was `isEmpty ? newGame() :
  loadPGN(_:)`, and both of those are public. Write the branch at the call site:

  ```swift
  if savedPGN.isEmpty {
      game.newGame()
  } else {
      _ = game.loadPGN(savedPGN)
  }
  ```

- **`Game.finishAnnotationRestore()`.** It was a byte-identical alias of
  `bumpNodeProperty()`, whose own documentation covers the batched-write case.
  Call `game.bumpNodeProperty()` instead — same effect, same coalesced bump.

- **`EngineAnalysis.Evaluation.displayText` and `.scoreText`.** Two spellings of
  one number (`"+1.30"` vs `"+1.3"`) in a library whose stated scope excludes
  presentation. How many decimal places to show is the caller's decision. Both
  bodies move downstream unchanged:

  ```swift
  extension EngineAnalysis.Evaluation {
      var displayText: String {
          switch self {
          case .winDrawLoss(let w, let d, let l):
              return String(format: "W %.0f%% D %.0f%% L %.0f%%", w * 100, d * 100, l * 100)
          case .centipawns(let cp):
              return String(format: "%+.2f", Double(cp) / 100.0)
          case .mate(let m):
              return "M\(abs(m))"
          }
      }
  }
  ```

  `UCIInfo.displayText` and `UCIInfo.Score.displayText` are unaffected and remain
  public — those spell a parsed UCI score, not an `Evaluation`.

- **`Piece.descriptiveName`** and **`MoveNode.spokenLabel(isCurrent:)`.**
  Composed English sentences, one of them carrying a list-selection flag. Copy
  them into the consumer, where they can be localized:

  ```swift
  extension Piece {
      var descriptiveName: String {
          let colorWord = color == .white ? "White" : "Black"
          return "\(colorWord) \(type.displayName)"
      }
  }

  extension MoveNode {
      func spokenLabel(isCurrent: Bool) -> String {
          let moveNumber = positionBefore.fullmoveNumber
          let isBlack = positionBefore.activeColor == .black
          let prefix = isBlack ? "\(moveNumber)..." : "\(moveNumber)."
          var label = "\(prefix) \(notation)"
          if let annotation { label += ", \(annotation.rawValue)" }
          if isCurrent { label += ", current" }
          return label
      }
  }
  ```

  `PieceType.displayName` stays: it is the noun that algebraic notation
  abbreviates. It is documented as English and explicitly not localized.

### Changed

- **`Game+ReplayInfo` is now `Game+PGNMetadata`**, with typed accessors named
  for the PGN tags they read rather than for the screen they fed:

  | Removed | Write instead |
  |---|---|
  | `game.hasReplayClockData` | `game.hasClockAnnotations` |
  | `game.replayClockTimes` | `game.clockTimes` |
  | `game.replayInitialClockTime` | `game.initialClockSeconds` |
  | `game.replayPlayerName(for:)` | `game.playerName(for:)` |
  | `game.replayPlayerELO(for:) -> String?` | `game.elo(for:) -> Int?` |
  | `game.hasReplayPlayerInfo(for:)` | *(removed — see below)* |

  `elo(for:)` returns `Int?`. It still filters the PGN placeholders (absent,
  empty, `"?"`, `"0"`), so the nil-ness contract is unchanged; only the type
  moved. To recover the old string:

  ```swift
  let text: String? = game.elo(for: color).map(String.init)
  ```

  `hasReplayPlayerInfo(for:)` was a render gate — it answered "should this panel
  appear", which is not a question about PGN. Ask it where the decision is made:

  ```swift
  func hasPlayerInfo(_ game: Game, for color: PieceColor) -> Bool {
      if let name = game.playerName(for: color), !name.isEmpty, name != "?" { return true }
      return game.elo(for: color) != nil
  }
  ```

- **`initialClockSeconds` parses the `TimeControl` forms the PGN specification
  defines**, not just base-plus-increment. `replayInitialClockTime` split on
  `"+"` and took the first field, so every form below except the first two
  returned `nil` or a wrong number. Behaviour change, not just a rename — a
  consumer that worked around the old parser should drop the workaround.

  | Tag | Meaning | Result |
  |---|---|---|
  | `600` | sudden death | `600` |
  | `300+5` | base plus increment | `300` |
  | `40/5400` | moves per period | `5400` |
  | `40/5400+30` | moves per period with increment | `5400` |
  | `*180` | hourglass / sandclock | `180` |
  | `40/5400:1800:*60` | multi-period | `5400` (first period) |
  | `-` / `?` | none / unknown | `nil` |

- **`EngineAnalysis.ScoredMove.probability` is `Double?`**, defaulting to `nil`.
  It is a policy network's output; a search engine had to invent a value, and
  `0` was indistinguishable from a genuine zero-probability move. A UCI engine
  now omits the argument at construction, and a reader unwraps:

  ```swift
  if let p = move.probability { show(p) } else { rankBy(move.score) }
  ```

- **`EngineError` cases are engine-neutral.** Rename at the switch:

  | Removed | Write instead |
  |---|---|
  | `.modelNotLoaded` | `.engineUnavailable` |
  | `.invalidInput` | `.invalidPosition` |
  | `.predictionFailed(String)` | `.analysisFailed(String)` |
  | `.noLegalMoves` | `.noLegalMoves` (unchanged) |

  `errorDescription` text is unchanged except for `.analysisFailed`, which now
  reads `"Analysis failed: …"` rather than `"Prediction failed: …"`.

- **`Position.stockfishSafeFEN` is now `Position.consistentFEN`** — named for
  the invariant it enforces rather than the one engine that asserts without it.
  The old name remains as a deprecated alias, so this is the one rename in this
  release that still compiles; you will get a warning, and Xcode's fix-it
  applies the rename. `stockfishSafeFEN` will be removed in a future minor.

### Fixed

- **`PGNParser.parseEngineComment` no longer eats Informant symbols out of
  prose.** An evaluation token must now contain a digit. Without that
  requirement `{+-}` and `{-+}` satisfied the character test — every character
  was in `+-.M0123456789` — and were parsed as evaluations, deleting them from
  the comment a reader had written. `{White is much better, +-}` now comes back
  with its prose intact.

- **`PGNParser.parseEngineComment` reads the PGN-reserved `[%eval …]` command**,
  in both its decimal (`[%eval -1.42]`) and mate (`[%eval #-3]`, reported as
  `"-M3"`) forms, alongside the existing `[%clk …]`. A `[%eval …]` tag wins over
  a bare evaluation token in the same comment, being the standardized spelling.

### Documentation

- Type documentation no longer explains itself by reference to a codebase the
  reader cannot see. Where that boundary information was load-bearing — `Game`
  holds no interaction state; `PieceColor`'s string forms are the web APIs' and
  FEN's — it is restated in general terms.
- Fixed a stacked comment block above `PGNParser.startingPosition(for:)`: three
  doc paragraphs for three different functions had collapsed onto one internal
  helper, leaving `mainLineSnapshot` and `parseMainLineSnapshot` undocumented.
- `MoveAnnotation` now states that four of its ten cases are review vocabulary
  with no PGN suffix, and that `pgnSuffix` is how to ask for only what the
  standard defines.
- The comment dialect `PGNExporter` writes is documented as this library's own
  format rather than as a standard.

## [0.8.0] — 2026-07-28

Breaking. Scoreless engine output and the fifty-move rule were both being
reported as something more definite than they are.

### Added

- `Game.canClaimDrawByFiftyMoveRule` — `true` while the halfmove clock is in
  `100 ..< 150` and the game is still playing. FIDE 9.3 makes fifty moves
  *claimable*; it does not end the game.

### Changed

- **The fifty-move rule no longer ends a game automatically.** `gameState`
  returns `.draw` at 150 halfmoves (the seventy-five-move rule, FIDE 9.6.2)
  rather than at 100. A consumer that surfaced the automatic draw at 100 should
  now offer a claim by reading `canClaimDrawByFiftyMoveRule`. Checkmate takes
  precedence over the automatic threshold.
- **`UCIInfo` reports an absent score as absent.** UCI permits useful scoreless
  lines such as `info depth 12 pv e2e4`, and those were being flattened into
  `cp 0` — a principal variation misread as an equal evaluation. Four members
  became optional:

  | Member | Was | Now |
  |---|---|---|
  | `UCIInfo.score` | `Score` | `Score?` |
  | `UCIInfo.centipawns` | `Int` | `Int?` |
  | `UCIInfo.whitePovCentipawns(sideToMoveIsWhite:)` | `Int` | `Int?` |
  | `UCIInfo.displayText` | `String` | `String?` |

  Unwrap rather than defaulting to zero — the whole point of the change is that
  "no score" and "equal" are different claims.

## [0.7.2] — 2026-07-21

### Fixed

- Restored Swift 6.0 compatibility (the declared toolchain floor).

### Changed

- CI: added an on-push Linux test gate on `ubuntu-latest`; updated the checkout
  action runtime.

### Documentation

- Dropped the private-repository installation caveat, corrected audited claims,
  and harmonized the README badge row across the package repositories.

## [0.7.1] — 2026-07-17

### Fixed

Pre-public hardening pass:

- A kingless FEN no longer crashes: it yields no legal moves and a safe game
  state.
- A SAN token ending in a multi-grapheme uppercase character parses to `nil`
  rather than trapping.
- A phantom en-passant target in a FEN no longer produces an illegal EP move.
- Added draw-state coverage across the fifty-move, seventy-five-move,
  repetition, and insufficient-material rules.

## [0.7.0] — 2026-07-17

### Added

- `Game.reconcilePath(from:toPlacementOf:maxPly:)` (static) — retract-aware path
  correction toward a target placement, without needing a live `Game`.
- CI publishes a GitHub Release automatically on a version-tag push.

### Fixed

- PGN: promotions written without `=` (the ChessUp coordinate dialect) now
  parse.

## [0.6.1] — 2026-07-15

### Changed

- Dropped a now-redundant `nonisolated(unsafe)` from the PGN statics.

## [0.6.0] — 2026-07-15

A benchmark-driven pass over the hot paths, each change measured on both macOS
and arm64 Linux. Perft node counts are the correctness oracle; all parsing and
export output is byte-identical to 0.5.1.

### Changed

Measured wins (Linux / Apple, best of five):

- `positionKey` / `repetitionKey` roughly 2.6× faster — the key is built from
  the four identity fields directly, and `MoveNode` caches its repetition key.
- `loadPGN` 12–14% faster on Linux — one legal-move list per ply, stdlib newline
  splitting instead of Foundation, and a lazily generated `MoveNode.id`.
- PGN export 51% faster on Linux — the `DateFormatter` is hoisted to a static.
- `UCIOutputParser.parseInfo` 6% faster on Linux — split tokens stay
  `[Substring]`.
- `perft` 5% faster on Linux, 7% on Apple — pseudo-legal moves are filtered to
  legal in one buffer.
- The `[%clk]` regex is compiled once and skipped entirely when the literal is
  absent.

Two candidates were measured and rejected rather than shipped: struct-of-arrays
magic tables (a ~6% perft regression on Linux) and packing `Square` to `Int8` (a
platform-split wash).

### Added

- `ChessCoreBench`, a release-only perft/parse harness, and an opt-in
  `PerfGuard` test gate. Neither is visible to library consumers.

### Changed

- Organization migration: `jaredbrewer` references retargeted to
  `fianchettochess`.

## [0.5.1] — 2026-07-14

### Fixed

- PGN rejects ambiguous SAN rather than picking a candidate.
- Player-identity matching rejects ambiguous matches.

## [0.5.0] — 2026-07-13

### Added

- **`GameTreeSnapshot`** — lossless game-tree snapshots with a stable schema,
  ordered structured tags, and enforced decode bounds.
- `PGNParser` diagnostics for tags-only records.

### Fixed

- `PGNParser` bounds live move-tree materialization and fails closed on snapshot
  desync.
- PGN tag values are escaped per §8.1 on export and unescaped on parse; the
  tag-value scanner is escape-aware (the first unescaped quote closes).
- `parseMainLineSnapshot` honors the `[FEN]` tag.
- `MoveNode` derives `moverColor` from `positionBefore.activeColor` rather than
  ply parity, and anchors move numbers to FEN state.
- `MoveNode` deinitializes iteratively, so a long chain no longer overflows the
  stack.
- Castling generation requires a friendly corner rook, with defense in depth in
  both `isLegal` and apply.
- Threefold detection no longer double-counts the start position.
- Move text that is missing the blank line after the tag pairs is no longer
  dropped.
- Bounded move text parses in linear time.

## [0.4.0] — 2026-07-10

### Added

- `MoveGenerator.legalCastlingUCIs` — castling-only legality without full move
  generation.

### Fixed

- Hardened chess-state and UCI validation.
- `PGNExporter` honors the start-position ply offset (FEN-setup numbering fix).

## [0.3.0] — 2026-07-06

### Added

- `Game`: a node-property invalidation counter, `reconcilePath`, and public
  `legalMoves`.

## [0.2.0] — 2026-07-05

Breaking. The scope boundary was drawn: analysis heuristics, opening data, and
application-specific engine types left the package.

### Removed

- Win-probability and `PositionEval` analysis heuristics.
- `OpeningBook` — ChessCore keeps foundational chess-game logic only.
- Application-specific analysis types formerly in `EngineTypes`.

### Added

- `UCIEngine`, the multi-engine transport seam.
- `Game.retractLastPlies` — deleting undone plies so a take-back's next move is
  main line rather than a variation.
- `PGNParser.loadGame` honors `[SetUp]` / `[FEN]` start positions.
- Shared spoken-label phrasing on `MoveNode` / `Piece` / `PieceType`. *(Removed
  again in 0.9.0 — see above.)*

### Fixed

- PGN comment-brace sanitization and `pliesLimit` prefix parsing.
- `parseInfo` rejects score-less, pv-less progress noise.
- Duplicate position-key serialization collapsed to one implementation.

## [0.1.1] — 2026-06-29

### Changed

- **`StockfishInfo` is now `UCIInfo`** — the generic UCI layer no longer names
  one engine.
- `EngineAnalysis`, `ScoredMove`, and `Evaluation` conform to `Sendable`.

### Added

- `Game.reconcile(toPlacementOf:)` — history-preserving correction toward a
  target position.
- CI workflow and Swift Package Index manifest.

## [0.1.0] — 2026-06-24

First tagged release: the position model, perft-verified magic-bitboard move
generation, FEN, SAN/UCI conversion, PGN parsing and export, the `Game` move
tree, and UCI engine-output parsing.

[0.9.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.9.0
[0.8.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.8.0
[0.7.2]: https://github.com/fianchettochess/ChessCore/releases/tag/0.7.2
[0.7.1]: https://github.com/fianchettochess/ChessCore/releases/tag/0.7.1
[0.7.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.7.0
[0.6.1]: https://github.com/fianchettochess/ChessCore/releases/tag/0.6.1
[0.6.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.6.0
[0.5.1]: https://github.com/fianchettochess/ChessCore/releases/tag/0.5.1
[0.5.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.5.0
[0.4.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.4.0
[0.3.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.3.0
[0.2.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.2.0
[0.1.1]: https://github.com/fianchettochess/ChessCore/releases/tag/0.1.1
[0.1.0]: https://github.com/fianchettochess/ChessCore/releases/tag/0.1.0
