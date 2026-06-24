import XCTest
@testable import FianchettoKit
import ChessCore

final class DTOTests: XCTestCase {

    func testPreparedGameDataFromPGNAndRoundTrip() throws {
        let pgn = """
        [White "Alice"]
        [Black "Bob"]
        [WhiteElo "2000"]
        [Result "1-0"]

        1. e4 e5 2. Nf3 1-0
        """
        let game = PGNParser.parse(pgn)[0]
        let dto = PreparedGameData(from: game, orderIndex: 5)
        XCTAssertEqual(dto.white, "Alice")
        XCTAssertEqual(dto.cachedWhiteElo, 2000)
        XCTAssertEqual(dto.cachedBlackElo, 0)
        XCTAssertEqual(dto.orderIndex, 5)
        XCTAssertEqual(dto.cachedMoveCount, 2)

        let encoded = try JSONEncoder().encode(dto)
        XCTAssertEqual(try JSONDecoder().decode(PreparedGameData.self, from: encoded), dto)

        // toPGNGame reconstructs the move list from the persisted text/tags.
        let rebuilt = PreparedGameData.toPGNGame(moveText: dto.moveText, tagsJSON: dto.tagsJSON, result: dto.result)
        XCTAssertEqual(rebuilt.moves, game.moves)
    }

    func testGameMetadataHelpers() {
        XCTAssertNil(PreparedGameData.parseSanitisedElo("?"))
        XCTAssertNil(PreparedGameData.parseSanitisedElo("0"))
        XCTAssertEqual(PreparedGameData.parseSanitisedElo(" 1850 "), 1850)
        XCTAssertEqual(PreparedGameData.normalizedGameID("?"), "")
        XCTAssertEqual(PreparedGameData.normalizedGameID("  https://lichess.org/abc  "), "https://lichess.org/abc")
        XCTAssertTrue(PreparedGameData.computeIsAnnotated(evalsJSON: "[0.1]", moveText: ""))
        XCTAssertTrue(PreparedGameData.computeIsAnnotated(evalsJSON: "", moveText: "1. e4 {; best e4} e5"))
        XCTAssertFalse(PreparedGameData.computeIsAnnotated(evalsJSON: "", moveText: "1. e4 e5"))
    }

    func testRepertoireDataRoundTripAndDisplayName() throws {
        let rep = RepertoireData(
            name: "",
            color: "black",
            moves: [RepertoireMoveData(positionKey: "k1", san: "c5"), RepertoireMoveData(positionKey: "k2", san: "Nf6", auditDismissed: true)]
        )
        XCTAssertEqual(rep.displayName, "Black Repertoire")
        let encoded = try JSONEncoder().encode(rep)
        XCTAssertEqual(try JSONDecoder().decode(RepertoireData.self, from: encoded), rep)
    }

    func testPersonalTrapDataRoundTrip() throws {
        let trap = PersonalTrapData(
            fen: "8/8/8/8/8/8/8/8 w - - 0 1", correctMoveUCI: "e2e4", userActualMoveUCI: "d2d4",
            gapCp: 250, halfMoveIndex: 7, sourceGameID: "g1", sourceOpeningName: "Italian",
            detectedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoded = try JSONEncoder().encode(trap)
        XCTAssertEqual(try JSONDecoder().decode(PersonalTrapData.self, from: encoded), trap)
    }

    func testFingerprintedCacheValidity() {
        let cache = FingerprintedCacheData(key: "tactics", fingerprint: 42, json: "[]", updatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(cache.isValid(against: 42))
        XCTAssertFalse(cache.isValid(against: 99))
    }
}
