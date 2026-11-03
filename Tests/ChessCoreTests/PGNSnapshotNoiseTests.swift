import XCTest
@testable import ChessCore

final class PGNSnapshotNoiseTests: XCTestCase {
    func testSnapshotSkipsLoaderNoiseSoReadableMovesAreNotLost() {
        let cases: [(String, [String])] = [
            ("1 e4 e5 2 Nf3", ["e4", "e5", "Nf3"]),
            ("e4 e5 ½-½", ["e4", "e5"]),
            ("e4 e5 1/2", ["e4", "e5"]),
        ]
        for (text, expected) in cases {
            let snapshot = PGNParser.mainLineSnapshot(fromMoveText: text)
            XCTAssertEqual(snapshot.moves.map(\.notation), expected, text)
            XCTAssertTrue(snapshot.diagnostics.isEmpty, text)
        }
    }
}
