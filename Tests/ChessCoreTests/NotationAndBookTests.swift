import XCTest
@testable import ChessCore

final class NotationAndBookTests: XCTestCase {

    func testPGNParseScholarsMate() {
        let pgn = """
        [Event "Test"]
        [White "A"]
        [Black "B"]
        [Result "1-0"]

        1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0
        """
        let games = PGNParser.parse(pgn)
        XCTAssertEqual(games.count, 1)
        let game = games[0]
        XCTAssertEqual(game.white, "A")
        XCTAssertEqual(game.result, "1-0")
        XCTAssertEqual(game.moves, ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7#"])
    }

    func testPGNMainLineSnapshotReachesMate() {
        let line = PGNParser.mainLineSnapshot(fromMoveText: "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#")
        XCTAssertEqual(line.moves.count, 7)
        let mate = line.moves.last!
        XCTAssertTrue(MoveGenerator.isInCheck(mate.positionAfter))
        XCTAssertFalse(MoveGenerator.hasAnyLegalMove(for: mate.positionAfter))
    }

    func testSANUCIRoundTrip() {
        let pos = Position.initial()
        // e4 as SAN -> Move -> UCI
        XCTAssertEqual(UCIParser.sanToUCI("e4", in: pos), "e2e4")
        // e2e4 as UCI -> SAN
        XCTAssertEqual(UCIParser.uciToSAN("e2e4", in: pos), "e4")
        let move = PGNParser.parseMove("e4", in: pos)
        XCTAssertEqual(move?.uci, "e2e4")
    }

    func testGameTagCodecRoundTripWithEscapes() {
        var tags = PGNGame.OrderedTags()
        tags["White"] = "Carlsen, Magnus"
        tags["Note"] = #"semis; with = and \ backslash"#  // exercises ; = \ escaping
        let encoded = GameTagCodec.encode(tags)
        let decoded = GameTagCodec.decode(encoded)
        XCTAssertEqual(decoded["White"], "Carlsen, Magnus")
        XCTAssertEqual(decoded["Note"], #"semis; with = and \ backslash"#)
        XCTAssertEqual(GameTagCodec.firstValue(forKey: "White", in: encoded), "Carlsen, Magnus")
    }

    func testStockfishInfoParsing() {
        let info = UCIOutputParser.parseInfo("info depth 20 score cp 35 multipv 1 pv e2e4 e7e5")
        XCTAssertEqual(info?.depth, 20)
        XCTAssertEqual(info?.score.centipawns, 35)
        XCTAssertEqual(info?.pv, ["e2e4", "e7e5"])
        XCTAssertNil(UCIOutputParser.parseInfo("info depth 20 score cp 35 lowerbound pv e2e4"))
        XCTAssertEqual(UCIOutputParser.parseBestMove("bestmove e2e4 ponder e7e5"), "e2e4")
    }
}
