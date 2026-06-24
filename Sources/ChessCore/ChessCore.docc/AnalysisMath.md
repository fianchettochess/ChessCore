# Analysis Math

The pure-logic layer over the model: accuracy aggregation, procedural endgame
generation, and consecutive-streak math.

## Overview

This layer is all pure functions over the model, so it can run off the main
actor: ``AccuracyAggregator`` for per-side / per-phase accuracy,
``EndgameArchetype`` (and ``CustomEndgameConfig``) for procedural endgame FENs,
and ``StreakMath`` for drill streaks.

## AccuracyAggregator

``AccuracyAggregator`` computes per-side, per-phase accuracy from a white-POV
centipawn array. It is a set of pure functions, so accuracy can be aggregated
across many games off the main actor.

It groups moves into buckets via ``AccuracyAggregator/moveBucketSize``,
``AccuracyAggregator/bucketStart(forMoveNumber:)``, and
``AccuracyAggregator/bucketLabel(start:)``, splits by
``AccuracyAggregator/Phase`` (opening / middlegame / endgame), and produces an
``AccuracyAggregator/GameAccuracy`` from a JSON eval array via
``AccuracyAggregator/accuracy(evalsJSON:startIsWhite:color:)``:

```swift
let acc = AccuracyAggregator.accuracy(
    evalsJSON: game.evalsJSON,    // a JSON array of white-POV centipawns
    startIsWhite: true,           // active color at move 1
    color: .white                 // the side you want accuracy for
)
```

The two formulas are shared across ChessCore:

- ``AccuracyAggregator/winProbability(cp:)`` is the logistic
  `1 / (1 + exp(-0.00368208 * cp))` — the same constant as
  ``StockfishInfo/Score`` and ``EngineAnalysis/Evaluation``.
- ``AccuracyAggregator/moveAccuracy(wpBefore:wpAfter:)`` maps the win-probability
  drop to a 0–100 accuracy:
  `min(100, max(0, 103.1668·exp(-0.04354·drop) − 3.1668))`.

> Note: ``AccuracyAggregator/GameAccuracy`` is a `public` type, but its stored
> properties are module-internal — outside ChessCore you obtain one from
> ``AccuracyAggregator/accuracy(evalsJSON:startIsWhite:color:)`` but cannot read
> its fields directly. The standalone
> ``AccuracyAggregator/winProbability(cp:)`` and
> ``AccuracyAggregator/moveAccuracy(wpBefore:wpAfter:)`` helpers are fully
> public.

## EndgameArchetype

``EndgameArchetype`` generates random legal endgame FENs for a trainer — each
case produces a fresh position matching its theme, for unlimited replay value.
``EndgameArchetype/displayCategory`` names the theme,
``EndgameArchetype/randomFEN()`` returns a fresh legal FEN, and
``EndgameArchetype/fallbackFEN`` is a known-good static position.

```swift
let fen = EndgameArchetype.kbnVsK.randomFEN()   // a fresh, legal K+B+N vs K
```

"Legal" means playable: the side not to move isn't in check, the side to move has
a legal move, the kings aren't adjacent, and so on. The position uses
``Position/stockfishSafeFEN``; if random generation can't satisfy the constraints
after ~200 attempts, it falls back to ``EndgameArchetype/fallbackFEN``.

### Custom endgames

``CustomEndgameConfig`` lets a user pick how many of each non-king piece each
side has, via a ``CustomEndgameConfig/PieceCounts`` per color. It exposes
``CustomEndgameConfig/totalPieces``, a ``CustomEndgameConfig/summary`` string, an
``CustomEndgameConfig/isValid`` check, ``CustomEndgameConfig/randomFEN()`` (which
returns `nil` if 200 retries can't satisfy it), and a
``CustomEndgameConfig/fallbackFEN``.

> Note: Positions with more than 7 pieces fall outside the Lichess tablebase, so
> the trainer skips win verification for them.

## StreakMath

``StreakMath`` is consecutive-correct streak math, shared by the drill stat
stores. Callers map attempts to `[Bool]` (most-recent last), then ask for the
trailing run with ``StreakMath/current(_:)`` or the longest run anywhere with
``StreakMath/best(_:)``:

```swift
let outcomes = [true, true, false, true, true, true]
StreakMath.current(outcomes)   // 3
StreakMath.best(outcomes)      // 3
```

## Utility helpers

``PercentFormat`` and ``EvalJSON`` round out the math layer —
``PercentFormat/whole(_:)`` formats a fraction as a whole-percent string (and
"—" for non-finite input), and ``EvalJSON/decode(_:)`` decodes a JSON string into
a white-POV centipawn array.

```swift
PercentFormat.whole(0.73)                 // "73%"  ("—" for non-finite)
EvalJSON.decode(jsonString)               // [Double]   white-POV centipawns
```

## See Also

- <doc:IntegratingAnEngine>
- <doc:StorageSeam>
- ``AccuracyAggregator``
- ``EndgameArchetype``
- ``StreakMath``
