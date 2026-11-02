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

    func testExportCarriesRoundedClockFieldsSoReadersKeepTheClock() throws {
        let cases: [(TimeInterval, String)] = [
            (59.96, "[%clk 0:01:00.0]"),
            (59.95, "[%clk 0:01:00.0]"),
            (9.97, "[%clk 0:00:10.0]"),
            (3599.96, "[%clk 1:00:00.0]"),
            (7199.96, "[%clk 2:00:00.0]"),
            (0.04, "[%clk 0:00:00.0]"),
            (65.34, "[%clk 0:01:05.3]"),
            (1.25, "[%clk 0:00:01.2]"),
            (1.15, "[%clk 0:00:01.1]"),
            (180, "[%clk 0:03:00]")
        ]
        for (seconds, expected) in cases {
            let game = Game()
            XCTAssertTrue(game.loadPGN("1. e4 *"))
            game.mainLine[0].clockSeconds = seconds
            let text = PGNExporter.moveText(for: game.rootChildren)
            XCTAssertTrue(text.contains(expected), "\(seconds): \(text)")
            let restored = Game()
            XCTAssertTrue(restored.loadPGN(text + " *"), "\(seconds): \(text)")
            let clock = try XCTUnwrap(restored.mainLine.first?.clockSeconds, "\(seconds): \(text)")
            XCTAssertEqual(clock, seconds, accuracy: 0.051, "\(seconds): \(text)")
        }
    }

    // MARK: - Implausible clocks

    /// The exporter converts through `Int`, which traps on anything it cannot
    /// hold, so one bad reading would otherwise crash every export, share and
    /// backup of its game.
    private static let unusableClocks: [TimeInterval] = [
        .nan, .infinity, -.infinity, 3.6e21, -5
    ]

    func testImportDropsAClockTooLargeToExport() throws {
        let pgn = "1. e4 {[%clk 1000000000000000000:00:00] sharp} e5 {[%clk 0:05:00]} *"

        let parsed = PGNParser.parseEngineComment("[%clk 1000000000000000000:00:00] sharp")
        XCTAssertNil(parsed.clockSeconds)
        XCTAssertEqual(parsed.comment, "sharp", "the tag still leaves the prose")

        let game = Game()
        XCTAssertTrue(game.loadPGN(pgn))
        XCTAssertNil(game.mainLine[0].clockSeconds)
        XCTAssertEqual(game.mainLine[0].comment, "sharp")
        XCTAssertEqual(game.mainLine[1].clockSeconds, 300, "a real clock beside it survives")
    }

    func testRestoringASnapshotDropsUnusableClocks() throws {
        for clock in Self.unusableClocks {
            let source = Game()
            XCTAssertTrue(source.loadPGN("1. e4 e5 *"))
            source.mainLine[0].clockSeconds = clock
            source.mainLine[1].clockSeconds = 300
            let snapshot = try GameTreeSnapshot(capturing: source)

            let restored = Game()
            try restored.restore(from: snapshot)

            XCTAssertNil(restored.mainLine[0].clockSeconds, "\(clock)")
            XCTAssertEqual(restored.mainLine[1].clockSeconds, 300, "\(clock)")
        }
    }

    func testExportOmitsAnUnusableClockAndKeepsTheRestOfTheComment() {
        for clock in Self.unusableClocks {
            let game = Game()
            XCTAssertTrue(game.loadPGN("1. e4 e5 *"))
            game.mainLine[0].clockSeconds = clock
            game.mainLine[1].clockSeconds = clock
            game.mainLine[1].comment = "sharp"

            XCTAssertEqual(
                PGNExporter.moveText(for: game.rootChildren).trimmingCharacters(in: .whitespaces),
                "1. e4 e5 {sharp}",
                "\(clock)"
            )
        }
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
