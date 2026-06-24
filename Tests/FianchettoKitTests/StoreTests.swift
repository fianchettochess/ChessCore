import XCTest
@testable import FianchettoKit
import ChessCore

final class StoreTests: XCTestCase {
    /// In-memory ``JSONBlobStore`` — the test/Android-style backend.
    final class MemoryBlobStore: JSONBlobStore {
        var storage: [String: String] = [:]
        func loadJSON(forKey key: String) -> String? { storage[key] }
        func saveJSON(_ json: String, forKey key: String) { storage[key] = json }
    }

    func testBlunderMasterySRS() {
        let store = MemoryBlobStore()
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        XCTAssertEqual(BlunderMasteryStore.mastery(fen: fen, correctSAN: "e4", in: store), 0)
        BlunderMasteryStore.record(fen: fen, correctSAN: "e4", correct: true, in: store)
        BlunderMasteryStore.record(fen: fen, correctSAN: "e4", correct: true, in: store)
        BlunderMasteryStore.record(fen: fen, correctSAN: "e4", correct: true, in: store)
        XCTAssertEqual(BlunderMasteryStore.mastery(fen: fen, correctSAN: "e4", in: store), 3)
        XCTAssertTrue(BlunderMasteryStore.isMastered(fen: fen, correctSAN: "e4", in: store))
        // Wrong resets the counter so the position resurfaces.
        BlunderMasteryStore.record(fen: fen, correctSAN: "e4", correct: false, in: store)
        XCTAssertEqual(BlunderMasteryStore.mastery(fen: fen, correctSAN: "e4", in: store), 0)
    }

    func testTacticsRatingEloMovesAndPersists() {
        let store = MemoryBlobStore()
        var rating = TacticsRatingStore()
        let start = rating.userRating
        // Beating a harder puzzle raises the user rating.
        let delta = rating.recordAttempt(puzzleKey: "p1", difficulty: .hard, outcome: .correct, in: store)
        XCTAssertGreaterThan(delta, 0)
        XCTAssertGreaterThan(rating.userRating, start)
        // Skips don't move ratings.
        XCTAssertEqual(rating.recordAttempt(puzzleKey: "p2", difficulty: .easy, outcome: .skipped, in: store), 0)
        // Persisted through the seam.
        let reloaded = TacticsRatingStore.load(from: store)
        XCTAssertEqual(reloaded.userRating, rating.userRating, accuracy: 0.0001)
    }

    func testTacticsPerformanceMetrics() {
        let store = MemoryBlobStore()
        var perf = TacticsPerformanceStore()
        func attempt(_ outcome: TacticsAttempt.Outcome) -> TacticsAttempt {
            TacticsAttempt(puzzleKey: "k", outcome: outcome, elapsedSeconds: 5, attemptOrdinal: 1, extractionMode: "punish", difficulty: "Easy")
        }
        perf.record(attempt(.correct), in: store)
        perf.record(attempt(.correct), in: store)
        perf.record(attempt(.wrong), in: store)
        XCTAssertEqual(perf.totalAttempts, 3)
        XCTAssertEqual(perf.accuracy, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(perf.bestStreak, 2)
        XCTAssertEqual(perf.currentStreak, 0)
    }

    func testTrainProgressCacheRoundTrip() {
        let store = MemoryBlobStore()
        XCTAssertNil(TrainProgressCache.snapshot(for: .tactics, from: store))
        TrainProgressCache.record(.init(total: 10, due: 4, mastered: 6), for: .tactics, into: store)
        XCTAssertEqual(TrainProgressCache.snapshot(for: .tactics, from: store), .init(total: 10, due: 4, mastered: 6))
        // Keys are per-mode.
        XCTAssertNil(TrainProgressCache.snapshot(for: .endgame, from: store))
    }

    func testRepertoireDrillStats() {
        let store = MemoryBlobStore()
        var stats = RepertoireDrillStats()
        let rep = UUID()
        stats.record(.init(correct: true, positionKey: "a"), in: rep, store: store)
        stats.record(.init(correct: false, positionKey: "b"), in: rep, store: store)
        XCTAssertEqual(stats.totalAttempts(for: rep), 2)
        XCTAssertEqual(stats.accuracy(for: rep), 0.5, accuracy: 0.0001)
        XCTAssertEqual(stats.recentOutcomes(for: rep), [true, false])
    }
}
