import Foundation

/// Pure-function accuracy maths so the stats cache can aggregate
/// across the user's annotated games without going through `Game` /
/// `MoveNode`. Operates directly on the white-POV centipawn array
/// produced by the annotation pipeline (`StoredGame.annotationEvalsJSON`).
///
/// Uses the same win-probability and per-move accuracy formulas as
/// `EngineManager+Annotation` so per-game values agree with what the
/// Game Review pane shows.
public nonisolated enum AccuracyAggregator {

    /// Coarse game-phase bucket. Boundaries are by full move number from
    /// the perspective of the first move in the game, not piece count —
    /// piece-count phase detection would mean re-parsing the PGN, and
    /// the dashboard's question ("when does my accuracy fall apart?")
    /// is sharp enough with simple move-number windows.
    public enum Phase: String, CaseIterable, Sendable {
        case opening, middlegame, endgame
        /// Move 1-10 is opening, 11-30 middlegame, 31+ endgame.
        static func bucket(forMoveNumber moveNumber: Int) -> Phase {
            if moveNumber <= 10 { return .opening }
            if moveNumber <= 30 { return .middlegame }
            return .endgame
        }
    }

    /// Per-side, per-phase accuracy values for a single game. Nil entries
    /// mean the side made no moves in that phase (e.g. the game ended in
    /// the opening), so the caller can skip them in averages instead of
    /// counting a missing phase as 0.
    public struct GameAccuracy: Sendable {
        let overall: Double?
        let phases: [Phase: Double]
        /// Accuracy bucketed by 5-move windows keyed on the *first* move
        /// number in the bucket (1, 6, 11, …). Lets a "where do I start
        /// losing the thread?" chart show finer detail than the coarse
        /// opening/middle/end split.
        let moveBuckets: [Int: Double]
    }

    /// Width of a `moveBuckets` window in full moves. Five is wide enough
    /// to dampen single-game noise but narrow enough to show a clear
    /// inflection point in a typical 40-move game.
    public static let moveBucketSize: Int = 5

    /// Convert a 1-indexed full-move number to its bucket's starting move
    /// number. `bucketStart(7) == 6`, `bucketStart(11) == 11`.
    public static func bucketStart(forMoveNumber moveNumber: Int) -> Int {
        let zeroBased = max(0, moveNumber - 1)
        return (zeroBased / moveBucketSize) * moveBucketSize + 1
    }

    public static func bucketLabel(start: Int) -> String {
        "\(start)–\(start + moveBucketSize - 1)"
    }

    /// Decode the white-POV centipawn array and compute per-phase
    /// accuracy for the requested side. `startIsWhite` should reflect
    /// the active colour at move 1 — true for the standard starting
    /// position, false for setups loaded from a FEN where Black is to
    /// move first.
    public static func accuracy(
        evalsJSON: String,
        startIsWhite: Bool,
        color: PieceColor
    ) -> GameAccuracy? {
        let evals = decode(evalsJSON)
        guard evals.count >= 2 else { return nil }

        var overallSum: Double = 0
        var overallCount: Int = 0
        var phaseSums: [Phase: Double] = [:]
        var phaseCounts: [Phase: Int] = [:]
        var bucketSums: [Int: Double] = [:]
        var bucketCounts: [Int: Int] = [:]

        for i in 0..<(evals.count - 1) {
            let movedColor = PieceColor.mover(ply: i, startIsWhite: startIsWhite)
            guard movedColor == color else { continue }

            // evals[i] is white-POV cp. Flip to mover-POV when computing
            // win probabilities so accuracy is "this side's chance of
            // winning before vs after their move".
            let wpWhiteBefore = winProbability(cp: evals[i])
            let wpWhiteAfter = winProbability(cp: evals[i + 1])
            let wpBefore = color == .white ? wpWhiteBefore : 1.0 - wpWhiteBefore
            let wpAfter = color == .white ? wpWhiteAfter : 1.0 - wpWhiteAfter

            let acc = moveAccuracy(wpBefore: wpBefore, wpAfter: wpAfter)
            overallSum += acc
            overallCount += 1

            let moveNumber = (i / 2) + 1
            let phase = Phase.bucket(forMoveNumber: moveNumber)
            phaseSums[phase, default: 0] += acc
            phaseCounts[phase, default: 0] += 1

            let bucket = bucketStart(forMoveNumber: moveNumber)
            bucketSums[bucket, default: 0] += acc
            bucketCounts[bucket, default: 0] += 1
        }

        guard overallCount > 0 else { return nil }
        let overall = overallSum / Double(overallCount)
        var phases: [Phase: Double] = [:]
        for (phase, sum) in phaseSums {
            let count = phaseCounts[phase] ?? 0
            guard count > 0 else { continue }
            phases[phase] = sum / Double(count)
        }
        var buckets: [Int: Double] = [:]
        for (start, sum) in bucketSums {
            let count = bucketCounts[start] ?? 0
            guard count > 0 else { continue }
            buckets[start] = sum / Double(count)
        }
        return GameAccuracy(overall: overall, phases: phases, moveBuckets: buckets)
    }

    // MARK: - Pure maths

    /// Logistic mapping from centipawns to win probability. Same constant
    /// (`0.00368208`) as `StockfishInfo.Score.winProbability` so per-game
    /// figures derived from the eval JSON match the on-the-fly Game
    /// Review numbers.
    public static func winProbability(cp: Double) -> Double {
        1.0 / (1.0 + exp(-0.00368208 * cp))
    }

    /// Per-move accuracy formula. Identical to
    /// `EngineManager.moveAccuracy` so dashboard aggregates line up
    /// with the per-game tile in `GameReviewView`.
    public static func moveAccuracy(wpBefore: Double, wpAfter: Double) -> Double {
        let drop = max(0, wpBefore - wpAfter) * 100
        let raw = 103.1668 * exp(-0.04354 * drop) - 3.1668
        return min(100, max(0, raw))
    }

    private static func decode(_ json: String) -> [Double] {
        EvalJSON.decode(json)
    }
}
