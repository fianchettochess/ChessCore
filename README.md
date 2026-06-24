# ChessCore

The portable, pure-Swift core carved out of the Fianchetto chess app so it can
be shared by the **Apple app** and the **Android (Skip/SkipFuse) port**.

**Foundation-only.** No SwiftData, CloudKit, GameKit, CoreML, UIKit, AppKit,
SwiftUI, Combine, or CoreBluetooth. Those Apple-bound concerns stay app-side
behind protocol seams (storage, engine-probe, sound/haptics, observation).

This is a **private** package — it carries product IP (tactics extraction,
repertoire auditing, trap mining, SRS, accuracy/Elo math). Consumed by both apps
as a local (path) dependency.

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
