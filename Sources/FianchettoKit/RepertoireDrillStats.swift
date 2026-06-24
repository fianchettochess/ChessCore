import Foundation
import ChessCore

/// Per-repertoire drill-history aggregate (accuracy %, streaks, last-N
/// sparkline). A `BlobBackedStore` over the ``JSONBlobStore`` seam; each rep's
/// attempt list is capped to bound growth.
public struct RepertoireDrillStats: Codable, BlobBackedStore {
    public var perRepertoire: [UUID: DrillHistory] = [:]
    public var schemaVersion: Int = 1

    public init() {}

    private static let maxAttemptsPerRep = 200

    // MARK: - Nested types

    public struct DrillHistory: Codable, Sendable, Hashable {
        public var attempts: [DrillAttempt] = []
        public var lastDrilled: Date?
        public init(attempts: [DrillAttempt] = [], lastDrilled: Date? = nil) {
            self.attempts = attempts
            self.lastDrilled = lastDrilled
        }
    }

    public struct DrillAttempt: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var timestamp: Date
        public var correct: Bool
        public var positionKey: String

        public init(id: UUID = UUID(), timestamp: Date = Date(), correct: Bool, positionKey: String) {
            self.id = id
            self.timestamp = timestamp
            self.correct = correct
            self.positionKey = positionKey
        }
    }

    // MARK: - Recording

    public mutating func record(_ attempt: DrillAttempt, in repertoireID: UUID, store: JSONBlobStore) {
        var history = perRepertoire[repertoireID] ?? DrillHistory()
        history.attempts.append(attempt)
        history.lastDrilled = attempt.timestamp
        history.attempts.capLast(Self.maxAttemptsPerRep)
        perRepertoire[repertoireID] = history
        save(to: store)
    }

    public mutating func resetAll(in store: JSONBlobStore) {
        perRepertoire.removeAll()
        save(to: store)
    }

    // MARK: - Queries

    public func history(for repertoireID: UUID) -> DrillHistory {
        perRepertoire[repertoireID] ?? DrillHistory()
    }

    public func totalAttempts(for repertoireID: UUID) -> Int {
        history(for: repertoireID).attempts.count
    }

    public func correctCount(for repertoireID: UUID) -> Int {
        history(for: repertoireID).attempts.lazy.filter { $0.correct }.count
    }

    public func accuracy(for repertoireID: UUID) -> Double {
        let attempts = history(for: repertoireID).attempts
        guard !attempts.isEmpty else { return 0 }
        let correct = attempts.filter { $0.correct }.count
        return Double(correct) / Double(attempts.count)
    }

    /// Current run of consecutive correct attempts (wrong breaks it).
    public func currentStreak(for repertoireID: UUID) -> Int {
        StreakMath.current(history(for: repertoireID).attempts.map(\.correct))
    }

    /// Best run of consecutive correct attempts in the history.
    public func bestStreak(for repertoireID: UUID) -> Int {
        StreakMath.best(history(for: repertoireID).attempts.map(\.correct))
    }

    /// Last `n` outcomes (most recent last) for the sparkline display.
    public func recentOutcomes(for repertoireID: UUID, last n: Int = 10) -> [Bool] {
        let attempts = history(for: repertoireID).attempts
        return Array(attempts.suffix(n)).map(\.correct)
    }

    // MARK: - Persistence (see BlobBackedStore)

    public static var blobKey: String { "repertoireDrillStats" }
}
