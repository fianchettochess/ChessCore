# Analysis Math

The pure-logic layer over the model: accuracy aggregation, procedural endgame
generation, and streak math.

## AccuracyAggregator

`AccuracyAggregator` computes per-side, per-phase accuracy from a white-POV
centipawn array. It is a set of pure functions, so accuracy can be aggregated
across many games off the main actor.

```swift
public enum AccuracyAggregator {
    public enum Phase: String, CaseIterable, Sendable { case opening, middlegame, endgame }

    public struct GameAccuracy: Sendable { /* opaque outside the module */ }

    public static let moveBucketSize: Int   // 5
    public static func bucketStart(forMoveNumber: Int) -> Int
    public static func bucketLabel(start: Int) -> String      // "6–10"
    public static func accuracy(evalsJSON: String, startIsWhite: Bool, color: PieceColor) -> GameAccuracy?
    public static func winProbability(cp: Double) -> Double
    public static func moveAccuracy(wpBefore: Double, wpAfter: Double) -> Double
}
```

```swift
let acc = AccuracyAggregator.accuracy(
    evalsJSON: game.evalsJSON,    // a JSON array of white-POV centipawns
    startIsWhite: true,           // active color at move 1
    color: .white                 // the side you want accuracy for
)
```

The two formulas are shared across ChessCore:

- `winProbability(cp:)` is the logistic `1 / (1 + exp(-0.00368208 * cp))` — the
  same constant as `StockfishInfo.Score.winProbability` and
  `EngineAnalysis.Evaluation.whiteWinProbability`.
- `moveAccuracy(wpBefore:wpAfter:)` maps the win-probability drop to a 0–100
  accuracy: `min(100, max(0, 103.1668·exp(-0.04354·drop) − 3.1668))`.

!!! note
    `GameAccuracy` is a `public` type, but its stored properties are
    module-internal — outside ChessCore you obtain one from `accuracy(...)` but
    cannot read its fields directly. The standalone `winProbability(cp:)` and
    `moveAccuracy(...)` helpers are fully public.

## EndgameArchetype

`EndgameArchetype` generates random legal endgame FENs for a trainer — each case
produces a fresh position matching its theme, for unlimited replay value.

```swift
public enum EndgameArchetype: String, Hashable, Codable, Sendable, CaseIterable {
    case kqVsK, krVsK, k2bVsK, kbnVsK, kpVsK, kqVsKp, lucena, philidor

    public var displayCategory: String   // "K+Q vs K", "Lucena", ...
    public func randomFEN() -> String
    public var fallbackFEN: String
}
```

```swift
let fen = EndgameArchetype.kbnVsK.randomFEN()   // a fresh, legal K+B+N vs K
```

"Legal" means playable: the side not to move isn't in check, the side to move has
a legal move, the kings aren't adjacent, and so on. The position uses
`stockfishSafeFEN`; if random generation can't satisfy the constraints after
~200 attempts, it falls back to a known-good static FEN.

### Custom endgames

`CustomEndgameConfig` lets a user pick how many of each non-king piece each side
has:

```swift
public struct CustomEndgameConfig: Hashable, Sendable, Codable {
    public var white: PieceCounts
    public var black: PieceCounts
    public var totalPieces: Int
    public var summary: String           // "K+R+P vs K+B+N"
    public var isValid: Bool             // totalPieces <= 32
    public func randomFEN() -> String?   // nil if 200 retries can't satisfy it
    public var fallbackFEN: String
}
```

Positions with more than 7 pieces fall outside the Lichess tablebase, so the
trainer skips win verification for them.

## StreakMath

Consecutive-correct streak math, shared by the drill stat stores. Callers map
attempts to `[Bool]` (most-recent last):

```swift
public enum StreakMath {
    public static func current(_ flags: [Bool]) -> Int   // trailing run of `true`
    public static func best(_ flags: [Bool]) -> Int      // longest run anywhere
}
```

```swift
let outcomes = [true, true, false, true, true, true]
StreakMath.current(outcomes)   // 3
StreakMath.best(outcomes)      // 3
```

## Utility helpers

```swift
PercentFormat.whole(0.73)                 // "73%"  ("—" for non-finite)
EvalJSON.decode(jsonString)               // [Double]   white-POV centipawns
PieceColor.mover(ply: 2, startIsWhite: true)   // .white
TimeInterval(95).clockString(showHours: false, showTenths: false)   // "1:35"
```
