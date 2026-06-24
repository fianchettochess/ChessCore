# ChessCore

The portable, pure-Swift core carved out of the Fianchetto chess app so it can
be shared by the **Apple app** and the **Android (Skip/SkipFuse) port**.

**Foundation-only.** No SwiftData, CloudKit, GameKit, CoreML, UIKit, AppKit,
SwiftUI, Combine, or CoreBluetooth. Those Apple-bound concerns stay app-side
behind protocol seams (storage, engine-probe, sound/haptics, observation).

This is a **private** package — it carries product IP (tactics extraction,
repertoire auditing, trap mining, SRS, accuracy/Elo math). Consumed by both apps
as a local (path) dependency.

**Deployment floor:** declared at **iOS 13 / macOS 10.15** (tvOS 13 / watchOS 6 /
visionOS 1) — independent of Fianchetto's iOS 18.6 / macOS 15.6. The code is pure
Swift stdlib + Foundation, verified to build down to **iOS 11 / macOS 10.10**, so
the floor can be lowered to iOS 12 / macOS 10.13 (Swift-ABI-stable line) for
maximum reach at no API cost if a public release wants it.

## Status

Extraction is **in progress**, dependency-ordered. See
`docs/ANDROID_CARVE_PLAN.md` in the app repo for the full tranche plan, the
keystone decoupling (splitting `ChessModel` into pure value types + an app-side
presentation extension), and the per-file decoupling approaches.

**Landed (tranche 1 — pure leaves):**
- `StreakMath` — consecutive-correct streak math (current/best run).
- `DebouncedWriter` — Foundation/Dispatch debounce utility.

**Landed (keystone — foundational model):** `ChessModel.swift` — the portable
value types `PieceColor`, `PieceType`, `Piece`, `Square`, `CastlingRights`,
`Move`, `MoveRecord`, `MoveAnnotation` (PGN/NAG logic), `MoveQuality`,
`GameState`, and `Position` (FEN parse/serialize, en-passant, insufficient
material, `stockfishSafeFEN`, `positionKey`). The iOS presentation that was
woven into these in the app (SwiftUI `Color`s, SF Symbols, asset names,
`@Observable` `MoveNode`, localizable text) stays app-side and reattaches as
extensions at integration time; `MoveNode` also waits on `MoveGenerator`
(tranche 3).

**Landed (tranche 3 — engine primitives over the model):**
- `MoveGenerator` — legal/pseudo-legal move generation, make-move, attack
  detection, SAN. Decoupled for portability: `OSAllocatedUnfairLock` →
  `NSLock`, the legal-moves cache now keys on `Position.positionKey` (breaking
  the back-dependency on OpeningBook), and `os.Logger` dropped. Validated by a
  **perft suite** (exact node counts — initial perft(4)=197281, Kiwipete
  perft(3)=97862, plus en-passant/promotion positions) that also pins behavior
  for a future magic-bitboard rewrite.
- `SharedUtilities` — `Position`/`PieceColor`/`PieceType` extensions
  (`materialSummary`, `mover(ply:)`, `fenStartsWithWhite`), `EvalJSON`,
  `PercentFormat`, `Array.capLast`, `TimeInterval.clockString`.
- `UCIOutputParser` — `StockfishInfo` (UCI `info`/`bestmove` payload, generic to
  the UCI protocol) + parsing; `os.Logger` dropped.

**Landed (tranche 4 — notation + book primitives):**
- `PGNTokenizer` — `PGNGame`/`OrderedTags`, `PGNToken`, `PGNParser`
  (tokenize/parse/`parseMove`/`Sendable` mainline snapshot), `PGNExporter`
  token serialization, `MainLineMoveSnapshot`/`ParsedMainLine`.
- `UCIParser` — SAN↔UCI translation (`uciToMove`/`uciToSAN`/`sanToUCI`/PV→SAN).
- `GameTagCodec` — escape-safe `key=value;…` PGN-tag codec.
- `OpeningBook` — ECO lookup + continuations with EP-transposition fallback.
  Decoupled: `OSAllocatedUnfairLock` → `NSLock`, `os.Logger` dropped, and
  `Bundle.main` resource loading replaced by injectable
  `OpeningBook(precomputedData:isPlist:)` / `configureShared(…)` (the app wires
  its bundle; Android wires its asset).
- `EngineTypes` — `ChessEngine` engine-probe protocol, `EngineAnalysis`/
  `ScoredMove`/`Evaluation`, `PlayConfig`, `EngineError`, etc. (`import SwiftUI`
  → `Foundation`).

**Landed (tranche 5 — endgame / traps / ratings / network):**
- `EndgameArchetype` (procedural endgame FEN generator) + `CustomEndgameConfig`,
  `OpeningTrap`, `SquareOffSyncGate`, `AccuracyAggregator` (win-probability +
  per-move accuracy curves) — pure logic over the model/primitives.
- `TablebaseService`, `LichessExplorer`, `ChessAPIService` (Lichess / Syzygy /
  Chess.com REST clients). Decoupled: `os.Logger` dropped; networking made
  portable via `#if canImport(FoundationNetworking)` (URLSession/URLRequest live
  in `FoundationNetworking` on non-Apple) and a back-deployed
  `URLSession.dataResult(for:)` (`bytes(for:)`'s AsyncBytes needs iOS 15/macOS
  12; `dataResult` keeps these on the iOS 13/macOS 10.15 floor + portable to
  Android).

All of the above build for `aarch64-unknown-linux-android28` and pass the unit
tests on macOS. These types are currently **copied** into ChessCore additively
— the app keeps its own definitions until the integration step (point the iOS
target at ChessCore via `@_exported import`, then delete the in-app copies).

## Intended internal boundary

- **Primitives** (commodity, could one day become a thin *public* package):
  move generation, FEN, SAN↔UCI, PGN parse/export, opening book, UCI
  engine-output parsing, REST clients.
- **Logic** (differentiated, stays private): tactics extraction, repertoire
  auditing/punish generation, personal trap mining, SRS/blunder-mastery,
  accuracy/Elo/streak math, Maia board encoding.

Both currently live in one `ChessCore` target; they will split into
`ChessCorePrimitives` + `ChessCore` once the volume justifies it. Keeping the
boundary clean now keeps the public-primitives option open at zero cost.

## Build

```bash
swift build            # macOS host
swift test             # run the unit tests

# Android (from a macOS host) — same mechanics as SwiftStockfish:
# a Swift toolchain matching the Android SDK + the NDK's llvm-ar librarian.
```
