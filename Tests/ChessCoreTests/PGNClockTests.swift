import XCTest
@testable import ChessCore

/// Guards `[%clk ...]` parsing, the `TimeControl` tag parser, and the typed
/// PGN player-tag accessors. The clock pattern is
/// `\[%clk\s+(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]`: hours are open-ended,
/// minutes and seconds are exactly two digits.
final class PGNClockTests: XCTestCase {
    func testClockSecondsParsing() {
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 1:30:05]").clockSeconds, 5405)
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 0:05:00]").clockSeconds, 300)
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 0:05:00.5]").clockSeconds, 300.5)
        // Multi-digit hours are allowed (\d+); minutes/seconds are exactly \d{2}.
        XCTAssertEqual(PGNParser.parseEngineComment("[%clk 12:00:00]").clockSeconds, 43200)
        // 1-digit minutes/seconds fail the \d{2} groups → no match.
        XCTAssertNil(PGNParser.parseEngineComment("[%clk 5:5:5]").clockSeconds)
        // No whitespace after `clk` fails \s+ → no match.
        XCTAssertNil(PGNParser.parseEngineComment("[%clk0:05:00]").clockSeconds)
        // No clock tag at all.
        XCTAssertNil(PGNParser.parseEngineComment("+1.2; best Nf3").clockSeconds)
    }

    // MARK: - Engine comments

    func testEngineCommentReadsTheLibrarysOwnExportFormat() {
        let parsed = PGNParser.parseEngineComment("+0.34; best Nf3; solid")
        XCTAssertEqual(parsed.eval, "+0.34")
        XCTAssertEqual(parsed.bestMove, "Nf3")
        XCTAssertEqual(parsed.comment, "solid")
    }

    func testEngineCommentReadsTheReservedEvalCommand() {
        XCTAssertEqual(PGNParser.parseEngineComment("[%eval -1.42]").eval, "-1.42")
        XCTAssertEqual(PGNParser.parseEngineComment("[%eval 0.17]").eval, "0.17")
        // Mate distances become the same M-spelling the export format uses.
        XCTAssertEqual(PGNParser.parseEngineComment("[%eval #3]").eval, "M3")
        XCTAssertEqual(PGNParser.parseEngineComment("[%eval #-3]").eval, "-M3")

        // Alongside a clock tag, and with prose left over.
        let both = PGNParser.parseEngineComment("[%eval 0.24] [%clk 0:05:00] good idea")
        XCTAssertEqual(both.eval, "0.24")
        XCTAssertEqual(both.clockSeconds, 300)
        XCTAssertEqual(both.comment, "good idea")
    }

    func testEngineCommentDoesNotEatInformantSymbols() {
        // An evaluation must contain a digit. Without that rule these satisfy
        // the character test and vanish out of the reader's prose.
        XCTAssertNil(PGNParser.parseEngineComment("+-").eval)
        XCTAssertEqual(PGNParser.parseEngineComment("+-").comment, "+-")
        XCTAssertNil(PGNParser.parseEngineComment("-+").eval)
        XCTAssertEqual(PGNParser.parseEngineComment("-+").comment, "-+")
        // Prose that merely begins with a sign is prose.
        XCTAssertEqual(PGNParser.parseEngineComment("-- an aside").comment, "-- an aside")
    }

    // MARK: - TimeControl tag

    func testTimeControlBaseSecondsCoversTheSpecForms() {
        // Absent / unknown / none.
        XCTAssertNil(Game.timeControlBaseSeconds("-"))
        XCTAssertNil(Game.timeControlBaseSeconds("?"))
        XCTAssertNil(Game.timeControlBaseSeconds(""))
        XCTAssertNil(Game.timeControlBaseSeconds("   "))

        // Sudden death.
        XCTAssertEqual(Game.timeControlBaseSeconds("600"), 600)

        // Increment and the rarer delay spelling.
        XCTAssertEqual(Game.timeControlBaseSeconds("300+5"), 300)
        XCTAssertEqual(Game.timeControlBaseSeconds("180-2"), 180)

        // Moves-per-period.
        XCTAssertEqual(Game.timeControlBaseSeconds("40/5400"), 5400)
        XCTAssertEqual(Game.timeControlBaseSeconds("40/5400+30"), 5400)

        // Sandclock / hourglass.
        XCTAssertEqual(Game.timeControlBaseSeconds("*180"), 180)

        // Multi-period: the clock starts on the first period.
        XCTAssertEqual(Game.timeControlBaseSeconds("40/5400:1800:*60"), 5400)
        XCTAssertEqual(Game.timeControlBaseSeconds("40/7200:20/3600:900+30"), 7200)

        // Junk stays junk rather than becoming a plausible-looking zero.
        XCTAssertNil(Game.timeControlBaseSeconds("blitz"))
        XCTAssertNil(Game.timeControlBaseSeconds("40/"))
    }

    func testInitialClockSecondsReadsTheTag() {
        let pgn = """
        [TimeControl "300+3"]

        1. e4 e5 *
        """
        let game = Game()
        XCTAssertTrue(game.loadPGN(pgn))
        XCTAssertEqual(game.initialClockSeconds, 300)

        let untimed = Game()
        XCTAssertTrue(untimed.loadPGN("1. e4 e5 *"))
        XCTAssertNil(untimed.initialClockSeconds)
    }

    // MARK: - Player tags

    func testPlayerNameAndEloReadTheSevenTagRoster() {
        let pgn = """
        [White "Carlsen, Magnus"]
        [Black "?"]
        [WhiteElo "2839"]
        [BlackElo "?"]

        1. e4 e5 *
        """
        let game = Game()
        XCTAssertTrue(game.loadPGN(pgn))

        XCTAssertEqual(game.playerName(for: .white), "Carlsen, Magnus")
        // The placeholder is returned as written — deciding what to do with it
        // is the caller's.
        XCTAssertEqual(game.playerName(for: .black), "?")

        XCTAssertEqual(game.elo(for: .white), 2839)
        XCTAssertNil(game.elo(for: .black))
    }

    func testEloRejectsPlaceholdersAndNonNumbers() {
        let pgn = """
        [WhiteElo "0"]
        [BlackElo "unrated"]

        1. e4 e5 *
        """
        let game = Game()
        XCTAssertTrue(game.loadPGN(pgn))
        XCTAssertNil(game.elo(for: .white), "\"0\" is a placeholder, not a rating")
        XCTAssertNil(game.elo(for: .black))
    }
}
