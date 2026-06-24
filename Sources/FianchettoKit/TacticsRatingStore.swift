import Foundation
import ChessCore

/// Elo-style rating model for tactics puzzles — the "motivational number" that
/// rises on tough solves and falls on flubbed easy ones. Zero-sum Elo, K=32:
/// each puzzle has its own rating (seeded from `PuzzleDifficulty`), and each
/// scored attempt moves the user rating by `K * (actual - expected)` and the
/// puzzle rating by the equal-and-opposite amount. A `BlobBackedStore` over the
/// ``JSONBlobStore`` seam.
public struct TacticsRatingStore: Codable, BlobBackedStore {
    public var userRating: Double = Self.defaultUserRating
    public var puzzleRatings: [String: PuzzleRating] = [:]
    /// Per-attempt rating snapshots for the trend chart (capped).
    public var ratingHistory: [RatingPoint] = []
    /// Per-repertoire performance counters for puzzles on a repertoire path.
    public var repertoirePerformance: [UUID: RepertoirePerformance] = [:]
    public var schemaVersion: Int = 1

    public init() {}

    private static let defaultUserRating: Double = 1400
    private static let kFactor: Double = 32
    private static let maxHistoryPoints = 200

    // MARK: - Nested types

    public struct PuzzleRating: Codable, Sendable, Hashable {
        public var rating: Double
        public var attemptCount: Int
        public var lastUpdated: Date
        public init(rating: Double, attemptCount: Int, lastUpdated: Date) {
            self.rating = rating
            self.attemptCount = attemptCount
            self.lastUpdated = lastUpdated
        }
    }

    public struct RatingPoint: Codable, Sendable, Hashable {
        public var timestamp: Date
        public var rating: Double
        public init(timestamp: Date, rating: Double) {
            self.timestamp = timestamp
            self.rating = rating
        }
    }

    public struct RepertoirePerformance: Codable, Sendable, Hashable {
        public var attempts: Int = 0
        public var correct: Int = 0
        public var avgPuzzleRating: Double = 0
        public var lastSolveAt: Date?
        public init() {}
    }

    // MARK: - Seed ratings

    /// Starting rating for a never-seen puzzle, from its static difficulty.
    public static func seedRating(for difficulty: PuzzleDifficulty) -> Double {
        switch difficulty {
        case .easy:   return 1200
        case .medium: return 1500
        case .hard:   return 1800
        }
    }

    // MARK: - Recording

    /// Update the user + puzzle ratings on one scored attempt. Returns the
    /// user-rating delta so the caller can flash a "+12"/"−9" indicator.
    @discardableResult
    public mutating func recordAttempt(
        puzzleKey: String,
        difficulty: PuzzleDifficulty,
        outcome: TacticsAttempt.Outcome,
        in store: JSONBlobStore
    ) -> Double {
        guard outcome != .skipped else { return 0 }

        var puzzleEntry = puzzleRatings[puzzleKey] ?? PuzzleRating(
            rating: Self.seedRating(for: difficulty),
            attemptCount: 0,
            lastUpdated: Date()
        )

        let actualScore: Double = (outcome == .correct) ? 1.0 : 0.0
        let expected = 1.0 / (1.0 + pow(10.0, (puzzleEntry.rating - userRating) / 400.0))
        let delta = Self.kFactor * (actualScore - expected)

        userRating += delta
        puzzleEntry.rating -= delta
        puzzleEntry.attemptCount += 1
        puzzleEntry.lastUpdated = Date()
        puzzleRatings[puzzleKey] = puzzleEntry

        ratingHistory.append(RatingPoint(timestamp: Date(), rating: userRating))
        ratingHistory.capLast(Self.maxHistoryPoints)

        save(to: store)
        return delta
    }

    /// Update the per-repertoire performance counters for each repertoire that
    /// contains the puzzle's position.
    public mutating func recordRepertoireAttempt(
        repertoireIDs: [UUID],
        puzzleRating: Double,
        correct: Bool,
        in store: JSONBlobStore
    ) {
        guard !repertoireIDs.isEmpty else { return }
        let timestamp = Date()
        for id in repertoireIDs {
            var counters = repertoirePerformance[id] ?? RepertoirePerformance()
            let prevSum = counters.avgPuzzleRating * Double(counters.attempts)
            counters.attempts += 1
            if correct {
                counters.correct += 1
                counters.lastSolveAt = timestamp
            }
            counters.avgPuzzleRating = (prevSum + puzzleRating) / Double(counters.attempts)
            repertoirePerformance[id] = counters
        }
        save(to: store)
    }

    /// Reset all ratings to default (settings-level "reset progress").
    public mutating func reset(in store: JSONBlobStore) {
        userRating = Self.defaultUserRating
        puzzleRatings.removeAll()
        ratingHistory.removeAll()
        repertoirePerformance.removeAll()
        save(to: store)
    }

    // MARK: - Queries

    /// Current rating of a puzzle, falling back to the seed if never attempted.
    public func rating(for puzzleKey: String, fallbackDifficulty: PuzzleDifficulty) -> Double {
        puzzleRatings[puzzleKey]?.rating ?? Self.seedRating(for: fallbackDifficulty)
    }

    /// Difficulty label relative to the user's own rating (nil if unattempted).
    public func relativeDifficulty(for puzzleKey: String) -> RelativeDifficulty? {
        guard let puzzleRating = puzzleRatings[puzzleKey]?.rating else { return nil }
        let gap = puzzleRating - userRating
        if gap >= 200 { return .veryHard }
        if gap >= 75  { return .hard }
        if gap >= -75 { return .even }
        if gap >= -200 { return .easy }
        return .veryEasy
    }

    public enum RelativeDifficulty: String, Sendable, CaseIterable {
        case veryEasy = "Very easy"
        case easy = "Easy"
        case even = "Even match"
        case hard = "Hard"
        case veryHard = "Very hard"
    }

    /// Current user rating, rounded for display.
    public var displayUserRating: Int { Int(userRating.rounded()) }

    /// Highest user-rating point ever recorded (the "personal best" badge).
    public var peakUserRating: Int {
        let peak = ratingHistory.map(\.rating).max() ?? userRating
        return Int(peak.rounded())
    }

    // MARK: - Persistence (see BlobBackedStore)

    public static var blobKey: String { "tacticsRating" }
}
