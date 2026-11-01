import XCTest
@testable import ChessCore

final class PGNLenientReportTests: XCTestCase {
    func testWrittenMoveNumbersGate() throws {
        let cases: [(String, Bool)] = [
            ("1. e4 e5 2. Nf3 Nc6 3. Bc4 4. Nf6", false),
            ("1. e4 e5 2. Nf3 3. Nc6 4. Bc4", false),
            ("1. d4 2. d5 3. c4", false), ("1. e4 2. e5", false),
            ("1. e4 999999999999999999999999. e5", false),
            ("1. e4 e5 2. Nf3", true), ("1. e4 {c} 1... e5 2. Nf3", true),
            ("1 e4 e5 2 Nf3", true), ("1.e4 e5 2.Nf3", true),
            ("1. e4 (1. d4 d5 2. c4) e5 2. Nf3", true),
            ("1. e4 e5 2. Nf3 N Nc6 3. Bb5", true)
        ]
        for (text, expected) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first)
            XCTAssertTrue(parsed.diagnostics.isEmpty, text)
            let scanned = PGNParser.tokenizeWithDiagnostics(text)
            XCTAssertEqual(scanned.hasInconsistentMoveNumbers, !expected, text)
            XCTAssertEqual(parsed.hasInconsistentMoveNumbers, !expected, text)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(report.hasInconsistentMoveNumbers, !expected, text)
            XCTAssertEqual(report.canReplaceStoredText, expected, text)
            var manual = PGNGame()
            manual.moveTokens = scanned.tokens
            manual.diagnostics = scanned.diagnostics
            manual.hasInconsistentMoveNumbers = scanned.hasInconsistentMoveNumbers
            XCTAssertEqual(try XCTUnwrap(PGNParser.loadGameWithReport(from: manual)).canReplaceStoredText, expected, text)
        }
        let fen = "[FEN \"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 20\"]\n\n20... Nf6 21. Nf3"
        let game = try XCTUnwrap(PGNParser.parse(fen).first)
        XCTAssertTrue(try XCTUnwrap(PGNParser.loadGameWithReport(from: game)).canReplaceStoredText)
        XCTAssertFalse(PGNGame().hasInconsistentMoveNumbers)
    }

    func testReportDistinguishesLostMovesFromNoiseAndMergedVariations() throws {
        let cases: [(String, [String])] = [
            ("1. e4 Zz9 2. d3 d5", ["Zz9", "d3"]),
            ("1. e4 e5 (1... Zz9 2. Nf3) 2. Nf3", ["Zz9", "Nf3"]),
            ("1. e4 {c} 1. ... e5 2. Nf3", []),
            ("1. e4 e5 2. Nf3 N Nc6", []),
            ("1. e4 e5 2. Nf3 += Nc6", []),
            ("1. e4 (1. e4) e5", []),
            ("1. e4 e5 (1... e5 2. Nf3) 2. Bc4", []),
            ("1 e4 e5 2 Nf3", []),
            ("1. e4 e5 1/2", []),
            ("1. e4 e5 ½-½", [])
        ]
        for (text, dropped) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(report.droppedMoveTokens, dropped, text)
            XCTAssertEqual(report.game.mainLine.map(\.notation), PGNParser.loadGame(from: parsed)?.mainLine.map(\.notation), text)
        }
    }
    func testMainLineReplayComparison() throws {
        let cases: [(String, Bool)] = [
            ("(1. d4) 1 e4 e5 2 Nf3", true),
            ("1 e4 e5 (1... e5 2. Nf3) 2 Bc4", true),
            ("1. e4 e5 (1... e5 2. Nf3) 2. Bc4 1/2", true),
            ("(1. d4 d5) 1. e4 e5 ½-½", true),
            ("(1. d4) 1. e4 e5", true),
            ("1. e4 {c} 1. ... e5 2. Nf3", false),
            ("1. e4 e5 2. Nf3 N Nc6", false),
            ("1. e4 e5 2. Nf3 += Nc6", false),
            ("1. e4 (1. e4) e5", false),
            ("1 e4 e5 2 Nf3", false)
        ]
        for (text, differs) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(report.mainLineDiffersFromSnapshot, differs, text)
        }
    }

    func testUnrecognizedFENAndReplacement() throws {
        for (tag, expected) in [("fen", true), ("FeN", true), ("FEN", false)] {
            var game = PGNGame()
            game.tags[tag] = Position.initial().fen
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: game))
            XCTAssertEqual(report.hasUnrecognizedSetupTag, expected, tag)
            XCTAssertEqual(report.canReplaceStoredText, !expected, tag)
        }
    }

    func testExportDepthLimitIsReported() throws {
        for depth in [63, 64, 65] {
            var input = PGNGame()
            var tokens: [PGNToken] = []
            for ply in 0...depth {
                tokens.append(.move(ply % 2 == 0 ? "Nc3" : "Nc6"))
                if ply < depth {
                    tokens.append(.variationStart)
                    let moves = ["Nf3", "Nf6", "Ng1", "Ng8"]
                    tokens.append(.move(moves[ply % 4]))
                }
            }
            tokens.append(contentsOf: Array(repeating: .variationEnd, count: depth))
            input.moveTokens = tokens
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: input))
            XCTAssertEqual(report.exceedsExportVariationDepth, depth >= 64, "depth \(depth)")
            XCTAssertEqual(PGNExporter.export(game: report.game).contains("truncated: variation depth limit"), depth >= 64)
        }
    }

    func testStoredMoveTextCarriesUnterminatedCommentDiagnostic() throws {
        let text = "1. e4 e5 {unterminated 2. Nf3 Nc6"
        let scanned = PGNParser.tokenizeWithDiagnostics(text)
        var game = PGNGame()
        game.moveTokens = scanned.tokens
        game.moves = PGNParser.flatMoves(from: scanned.tokens)
        game.diagnostics = scanned.diagnostics

        XCTAssertEqual(game.moves, ["e4", "e5"])
        XCTAssertEqual(game.diagnostics, [.unterminatedBraceComment])
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: game))
        XCTAssertTrue(report.hasUnterminatedBraceComment)
    }

    func testReportWarnsWhenUnterminatedCommentOrLeadingVariationCanLoseMainLine() throws {
        let comment = try XCTUnwrap(PGNParser.parse("1. e4 e5 {unterminated 2. Nf3 Nc6").first)
        XCTAssertTrue(try XCTUnwrap(PGNParser.loadGameWithReport(from: comment)).hasUnterminatedBraceComment)
        let leading = try XCTUnwrap(PGNParser.parse("(1. d4) 1. e4 e5").first)
        XCTAssertEqual(try XCTUnwrap(PGNParser.loadGameWithReport(from: leading)).mainLineDiffersFromSnapshot, true)
    }
}
