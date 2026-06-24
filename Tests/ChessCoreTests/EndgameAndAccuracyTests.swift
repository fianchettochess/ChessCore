import XCTest
@testable import ChessCore

final class EndgameAndAccuracyTests: XCTestCase {

    func testEndgameArchetypeFENsAreValid() {
        for arch in EndgameArchetype.allCases {
            // Deterministic fallback FEN parses and is well-formed.
            let fb = Position(fen: arch.fallbackFEN)
            XCTAssertNotNil(fb, "fallbackFEN invalid for \(arch)")
            // Random generations parse and always have exactly two kings.
            for _ in 0..<10 {
                guard let pos = Position(fen: arch.randomFEN()) else {
                    XCTFail("randomFEN invalid for \(arch)")
                    continue
                }
                let kings = pos.board.compactMap { $0 }.filter { $0.type == .king }
                XCTAssertEqual(kings.count, 2, "expected exactly two kings in \(arch)")
            }
            XCTAssertFalse(arch.displayCategory.isEmpty)
        }
    }

    func testWinProbabilityCurve() {
        XCTAssertEqual(AccuracyAggregator.winProbability(cp: 0), 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(AccuracyAggregator.winProbability(cp: 300), 0.7)
        XCTAssertLessThan(AccuracyAggregator.winProbability(cp: -300), 0.3)
    }

    func testMoveAccuracyEndpoints() {
        // No win-probability drop → ~100% accuracy.
        XCTAssertGreaterThan(AccuracyAggregator.moveAccuracy(wpBefore: 0.6, wpAfter: 0.6), 99)
        // A large drop (winning → losing) → low accuracy.
        XCTAssertLessThan(AccuracyAggregator.moveAccuracy(wpBefore: 0.8, wpAfter: 0.2), 30)
    }
}
