import XCTest
@testable import ChessCore

final class PGNRecordBoundaryTests: XCTestCase {
    func testNoteAndRecordBoundariesPreventLosingGameMovesOnImport() throws {
        let cases: [(String, [[String]], [String?])] = [
            ("1. e4 e5\n[diagram]\n2. Nf3 Nc6", [["e4", "e5", "[diagram]", "Nf3", "Nc6"]], [nil]),
            ("1. e4 e5\n[%csl Ga1]\n2. Nf3", [["e4", "e5", "[%csl", "Ga1]", "Nf3"]], [nil]),
            ("1. e4 e5\n\n[diagram]\n\n2. Nf3", [["e4", "e5"], ["Nf3"]], [nil, nil]),
            ("[Event \"A\"]\n1.e4 e5 1-0\n\n[BadTag]\n1-0\n\n[Event \"C\"]\n1.d4 1-0", [["e4", "e5"], [], ["d4"]], ["1-0", "1-0", "1-0"]),
            ("1. e4 *\n[Event A]\n[White B]\n1. d4 *", [["e4"], ["d4"]], ["*", "*"]),
            ("1. e4 e5 1-0\n[Game2]\n1. d4 d5 0-1", [["e4", "e5"], ["d4", "d5"]], ["1-0", "0-1"]),
            ("1. e4 e5 *\n[1]\n1. d4 d5 *", [["e4", "e5"], ["d4", "d5"]], ["*", "*"]),
            ("1. e4 e5\n[Game2]\n1. d4 d5", [["e4", "e5"], ["d4", "d5"]], [nil, nil]),
            ("1. e4 e5\n[Game2]\n\n1. d4 d5", [["e4", "e5"], ["d4", "d5"]], [nil, nil]),
            ("1. e4\n[diagram]\n1... e5 2. Nf3", [["e4", "[diagram]", "e5", "Nf3"]], [nil]),
            ("1. e4 1-0\n[Game2]\nd4 d5", [["e4"], ["d4", "d5"]], ["1-0", nil]),
            ("1. e4\n[Event A]\nd4 d5", [["e4"], ["d4", "d5"]], [nil, nil]),
            ("1. e4\n[_2 value]\nd4 d5", [["e4"], ["d4", "d5"]], [nil, nil])
        ]
        for (text, moves, results) in cases {
            let games = PGNParser.parse(text)
            XCTAssertEqual(games.map(\.moves), moves, text)
            XCTAssertEqual(games.map(\.result), results, text)
        }
        let parsed = try XCTUnwrap(PGNParser.parse(cases[0].0).first)
        XCTAssertTrue(PGNExporter.tokenText(from: parsed).contains("[diagram]"))
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
        XCTAssertEqual(report.droppedMoveTokens, ["[diagram]"])
        XCTAssertFalse(report.canReplaceStoredText)
        XCTAssertEqual(PGNExporter.moveText(for: report.game.rootChildren).trimmingCharacters(in: .whitespacesAndNewlines), "1. e4 e5 2. Nf3 Nc6")
    }

    func testNoteSnapshotsAndBoundariesKeepGamesReadableAndSeparate() throws {
        for prefix in ["", "[Event \"A\"]\n"] {
            let game = try XCTUnwrap(PGNParser.parse(prefix + "1. e4 e5\n[diagram]\n2. Nf3 Nc6").first)
            XCTAssertEqual(PGNParser.parseMainLineSnapshot(from: game).moves.count, 4)
            XCTAssertFalse(try XCTUnwrap(PGNParser.loadGameWithReport(from: game)).canReplaceStoredText)
        }
        for suffix in ["", "\n[Event \"B\"]\n1. d4 d5 0-1"] {
            let games = PGNParser.parse("[Event \"A\"]\n1. e4 e5 2. Nf3\n[diagram]" + suffix)
            XCTAssertEqual(games.count, suffix.isEmpty ? 1 : 2)
            XCTAssertEqual(games[0].moves, ["e4", "e5", "Nf3"])
            XCTAssertTrue(try XCTUnwrap(PGNParser.loadGameWithReport(from: games[0])).canReplaceStoredText)
        }
    }

    func testResultAndRestartNoiseCannotMergeSeparateGamesOrLoseResults() {
        let endings: [(String, String?)] = [("1-0 {White wins}", "1-0"), ("0-1 ; note", "0-1"),
                                          ("1/2-1/2 $1", "1/2-1/2"), ("½-½", nil), ("1/2", nil)]
        for (ending, result) in endings {
            let text = "1. e4 e5 " + ending + "\n[Game2]\nd4 d5 0-1"
            let games = PGNParser.parse(text)
            XCTAssertEqual(games.map(\.result), [result, "0-1"], text)
            XCTAssertEqual(games.count, 2, text)
        }
        for start in ["{note} 1. d4 d5", "$1 1 d4 d5", "% escape\n; comment\n1. d4 d5"] {
            let games = PGNParser.parse("1. e4 e5\n[Game2]\n" + start)
            XCTAssertEqual(games.count, 2, start)
            XCTAssertEqual(games.map { PGNParser.parseMainLineSnapshot(from: $0).moves.count }, [2, 2], start)
        }
        // Without a result, Black's move one can also continue the first game.
        XCTAssertEqual(PGNParser.parse("1. e4\n[diagram]\n1... e5").count, 1)
    }

    func testOversizedGameNoteCannotCreateTruncatedImport() {
        let text = "1. d4 {" + String(repeating: "x", count: 40) + "}\n[diagram]\n2. c4 d5 *"
        XCTAssertTrue(PGNParser.parse(text, maximumMoveTextBytes: 24).isEmpty)
    }

    func testLeadingBOMDoesNotLoseFirstGameTagsOrChangeParsedGames() throws {
        for newline in ["\n", "\r\n"] {
            let text = ["[Event \"First\"]", "[White \"Alice\"]", "", "1.e4 {note} e5 1-0", "",
                        "[Event \"Second\"]", "[Black \"Bob\"]", "", "1.d4 d5 *"].joined(separator: newline)
            let expected = PGNParser.parse(text)
            let actual = PGNParser.parse("\u{FEFF}" + text)
            XCTAssertEqual(expected.count, 2)
            XCTAssertEqual(actual.count, expected.count)
            for (game, reference) in zip(actual, expected) {
                XCTAssertEqual(game.tags, reference.tags)
                XCTAssertEqual(game.moves, reference.moves)
                XCTAssertEqual(game.result, reference.result)
                XCTAssertEqual(PGNExporter.tokenText(from: game), PGNExporter.tokenText(from: reference))
                XCTAssertEqual(game.diagnostics, reference.diagnostics)
                XCTAssertEqual(game.hasInconsistentMoveNumbers, reference.hasInconsistentMoveNumbers)
                XCTAssertEqual(game.variationWrittenOffsets, reference.variationWrittenOffsets)
            }
            XCTAssertEqual(actual.first?.tags["Event"], "First")
        }
    }

    private func comments(_ game: PGNGame) -> [String] {
        game.moveTokens.compactMap { if case .comment(let text) = $0 { return text }; return nil }
    }

    func testTagLookingBraceProseStaysInTheSameGame() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let moveText = "1.e4 {first" + newline + "[Event \"quoted\"]" + newline + "last} e5 *"
            let direct = PGNParser.tokenize(moveText)
            XCTAssertEqual(PGNParser.flatMoves(from: direct), ["e4", "e5"])
            let games = PGNParser.parse("[Event \"Outer\"]" + newline + moveText)
            XCTAssertEqual(games.count, 1)
            let game = try XCTUnwrap(games.first)
            XCTAssertEqual(game.tags["Event"], "Outer")
            XCTAssertEqual(game.moves, ["e4", "e5"])
            XCTAssertEqual(comments(game), ["first\n[Event \"quoted\"]\nlast"])
        }
    }

    func testStandaloneEngineCommandsInsideBracesAreNotTags() throws {
        let game = try XCTUnwrap(PGNParser.parse("[Event \"Engine\"]\n1.e4 {note\n[%eval 0.30]\nmore} e5 *").first)
        XCTAssertEqual(game.moves, ["e4", "e5"])
        XCTAssertEqual(comments(game), ["note\n[%eval 0.30]\nmore"])
        let loaded = try XCTUnwrap(PGNParser.loadGame(from: game))
        XCTAssertEqual(loaded.rootChildren.first?.engineEval, "0.30")
    }

    func testClosingBraceOnATagLookingLineAllowsTheNextRecord() {
        let text = "[Event \"First\"]\n1.e4 {first\n[prose } ; ignore ]\ne5 *\n[Event \"Second\"]\n1.d4 d5 *"
        let games = PGNParser.parse(text)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.first?.tags["Event"], "First")
        XCTAssertEqual(games.first?.moves, ["e4", "e5"])
        XCTAssertEqual(games.last?.tags["Event"], "Second")
        XCTAssertEqual(games.last?.moves, ["d4", "d5"])
    }

    func testBracesInLineCommentsDoNotHideTheNextRecord() {
        for newline in ["\n", "\r\n", "\r"] {
            let text = "[Event \"First\"]" + newline + "1.e4 ; { is prose" + newline
                + "[Event \"Second\"]" + newline + "1.d4 d5 *"
            let games = PGNParser.parse(text)
            XCTAssertEqual(games.count, 2)
            XCTAssertEqual(games.first?.moves, ["e4"])
            XCTAssertEqual(games.last?.tags["Event"], "Second")
            XCTAssertEqual(games.last?.moves, ["d4", "d5"])
        }
    }

    func testSemicolonsAndOpeningBracesInsideBracesDoNotHideTheNextRecord() {
        let text = "[Event \"First\"]\n1.e4 {keep; an opening { is literal}\n[Event \"Second\"]\n1.d4 d5 *"
        let games = PGNParser.parse(text)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.first?.moves, ["e4"])
        XCTAssertEqual(games.last?.moves, ["d4", "d5"])
    }

    func testEOFInsideABraceCommentDoesNotManufactureARecord() {
        let games = PGNParser.parse("[Event \"Outer\"]\n1.e4 {unfinished\n[Event \"prose\"]")
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.tags["Event"], "Outer")
        XCTAssertEqual(games.first?.moves, ["e4"])
        XCTAssertEqual(games.first?.diagnostics, [.unterminatedBraceComment])
    }

    func testOnlyACommentThatNeverClosesEndsAtTheNextRecord() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let stray = ["[Event \"A\"]", "", "1.e4 {stray e5 2.Nf3 *", "",
                         "[Event \"B\"]", "", "1.d4 {closed} d5 *", "",
                         "[Event \"C\"]", "", "1.c4 c5 *"].joined(separator: newline)
            let games = PGNParser.parse(stray)
            XCTAssertEqual(games.map { $0.tags["Event"] }, ["A", "B", "C"])
            XCTAssertEqual(games.map(\.moves), [["e4"], ["d4", "d5"], ["c4", "c5"]])
            XCTAssertEqual(games.map(\.diagnostics), [[.unterminatedBraceComment], [], []])

            // The same shape with a closing brace is prose quoting a record.
            let quoted = ["[Event \"Outer\"]", "", "1.e4 {compare", "",
                          "[Event \"Quoted\"]", "", "1.d4 d5} e5 *", "",
                          "[Event \"Next\"]", "", "1.c4 *"].joined(separator: newline)
            let quotedGames = PGNParser.parse(quoted)
            XCTAssertEqual(quotedGames.map { $0.tags["Event"] }, ["Outer", "Next"])
            XCTAssertEqual(quotedGames.first?.moves, ["e4", "e5"])
            XCTAssertEqual(quotedGames.first?.diagnostics, [])
        }
    }

    func testOverflowedCommentCannotManufactureARecordAndFollowingGameSurvives() {
        let text = "[Event \"Large\"]\n1.e4 {begin\n" + String(repeating: "oversized ", count: 10)
            + "\n[Event \"Fake\"]\nclosing} e5 *\n[Event \"Good\"]\n1.d4 d5 *"
        let games = PGNParser.parse(text, maximumMoveTextBytes: 24)
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.tags["Event"], "Good")
        XCTAssertEqual(games.first?.moves, ["d4", "d5"])
    }
}
