import Foundation
import ChessCore

/// Per-attempt tactics performance history (accuracy, streaks, timing, theme
/// breakdowns). A `BlobBackedStore` persisted over the ``JSONBlobStore`` seam.
/// Capped at `maxAttempts` to stay under CloudKit's ~1 MB record limit on the
/// Apple backend.
public struct TacticsPerformanceStore: Codable, BlobBackedStore {
    public var attempts: [TacticsAttempt] = []
    public var schemaVersion: Int = 1

    public init() {}

    /// Hard bound on retained history. At ~292 B JSON/attempt the blob crosses
    /// CloudKit's ~1 MB record limit near ~3,400 attempts; 3,000 keeps the worst
    /// case ~0.88 MB. Oversized legacy blobs decode in full and shrink to the
    /// cap on the next `record`.
    public static let maxAttempts = 3_000

    // MARK: - Recording

    public mutating func record(_ attempt: TacticsAttempt, in store: JSONBlobStore) {
        attempts.append(attempt)
        attempts.capLast(Self.maxAttempts)
        save(to: store)
    }

    /// Clear all attempt history (settings-level "reset progress").
    public mutating func reset(in store: JSONBlobStore) {
        attempts.removeAll()
        save(to: store)
    }

    // MARK: - Computed metrics

    public var totalAttempts: Int { attempts.count }
    public var correctCount: Int { attempts.lazy.filter { $0.outcome == .correct }.count }
    public var wrongCount: Int { attempts.lazy.filter { $0.outcome == .wrong }.count }
    public var skippedCount: Int { attempts.lazy.filter { $0.outcome == .skipped }.count }

    /// Total accuracy (correct ÷ (correct + wrong); skips excluded).
    public var accuracy: Double {
        let denom = correctCount + wrongCount
        guard denom > 0 else { return 0 }
        return Double(correctCount) / Double(denom)
    }

    /// Current run of consecutive correct attempts (wrong/skipped break it).
    public var currentStreak: Int {
        StreakMath.current(attempts.map { $0.outcome == .correct })
    }

    /// Longest run of consecutive correct attempts in the history.
    public var bestStreak: Int {
        StreakMath.best(attempts.map { $0.outcome == .correct })
    }

    /// Rolling accuracy over the last `n` answered attempts (skips excluded).
    public func recentAccuracy(over n: Int) -> Double {
        let recent = attempts.suffix(n * 2)
            .filter { $0.outcome != .skipped }
            .suffix(n)
        guard !recent.isEmpty else { return 0 }
        let correct = recent.filter { $0.outcome == .correct }.count
        return Double(correct) / Double(recent.count)
    }

    /// Median elapsed solve time over correct attempts (capped at 300 s to keep
    /// an outlier from skewing it). Nil if there are no correct attempts.
    public var medianSolveSeconds: Double? {
        let times = attempts
            .lazy
            .filter { $0.outcome == .correct }
            .map { min($0.elapsedSeconds, 300) }
            .sorted()
        guard !times.isEmpty else { return nil }
        let mid = times.count / 2
        if times.count % 2 == 1 { return times[mid] }
        return (times[mid - 1] + times[mid]) / 2
    }

    /// Attempts on or after `date`, oldest first.
    public func attempts(since date: Date) -> [TacticsAttempt] {
        attempts.filter { $0.timestamp >= date }
    }

    /// Per-difficulty correctness breakdown, keyed by the difficulty label.
    public func difficultyBreakdown() -> [String: (correct: Int, wrong: Int)] {
        var out: [String: (correct: Int, wrong: Int)] = [:]
        for attempt in attempts where attempt.outcome != .skipped {
            var entry = out[attempt.difficulty] ?? (0, 0)
            if attempt.outcome == .correct { entry.correct += 1 } else { entry.wrong += 1 }
            out[attempt.difficulty] = entry
        }
        return out
    }

    /// Per-extraction-mode breakdown (punish / your-blunders / critical / …).
    public func modeBreakdown() -> [String: (correct: Int, wrong: Int)] {
        var out: [String: (correct: Int, wrong: Int)] = [:]
        for attempt in attempts where attempt.outcome != .skipped {
            var entry = out[attempt.extractionMode] ?? (0, 0)
            if attempt.outcome == .correct { entry.correct += 1 } else { entry.wrong += 1 }
            out[attempt.extractionMode] = entry
        }
        return out
    }

    // MARK: - Persistence (see BlobBackedStore)

    public static var blobKey: String { "tacticsPerformance" }
}

// MARK: - Attempt

/// Single record of one user attempt at a tactics puzzle. `extractionMode` and
/// `difficulty` are stored as raw strings so the schema doesn't chase enum
/// cases.
public struct TacticsAttempt: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    /// `"<fen>:<correctSAN>"` — matches `BlunderMasteryStore`'s key convention.
    public var puzzleKey: String
    public var outcome: Outcome
    /// Wall-clock seconds between board setup and the answer (time-until-skip
    /// for skips).
    public var elapsedSeconds: Double
    /// 1 = first attempt at this puzzle in the session, 2 = second, etc.
    public var attemptOrdinal: Int
    public var timestamp: Date
    public var extractionMode: String
    public var difficulty: String

    public enum Outcome: String, Codable, Sendable {
        case correct
        case wrong
        case skipped
    }

    public init(
        id: UUID = UUID(),
        puzzleKey: String,
        outcome: Outcome,
        elapsedSeconds: Double,
        attemptOrdinal: Int,
        timestamp: Date = Date(),
        extractionMode: String,
        difficulty: String
    ) {
        self.id = id
        self.puzzleKey = puzzleKey
        self.outcome = outcome
        self.elapsedSeconds = elapsedSeconds
        self.attemptOrdinal = attemptOrdinal
        self.timestamp = timestamp
        self.extractionMode = extractionMode
        self.difficulty = difficulty
    }
}
