import XCTest
@testable import ChessCore

final class PGNInferredPawnCaptureTests: XCTestCase {
    /// Gates the import warning without changing the inferred move. A SAN or
    /// replay refactor could suppress or duplicate it, hiding a guessed capture
    /// from users or making their stored games appear corrupt.
    func testFilelessPawnCapturesEmitExactlyOneNonFatalNoticeAtTheirPlyWithoutChangingImportedMoves() throws {
        let cases: [(String, [PGNLoadNotice])] = [
            ("1. e4 d5 2. d5", [.inferredPawnCapture(san: "d5", plyIndex: 2)]),
            ("1. e4 d5 2. d5!", [.inferredPawnCapture(san: "d5!", plyIndex: 2)]),
            ("1. e4 d5 2. Pd5", [.inferredPawnCapture(san: "Pd5", plyIndex: 2)]),
            ("1. e4 d5 2. ed5", []),
            ("1. e4 d5 2. exd5", []),
            ("1. e4 d5 2. e4d5", []),
            ("1. e4 d5 2. Pe4d5", []),
            ("1. e4 e5 2. Nf3", []),
            ("1. e4 a6 2. e5 d5 3. d6", [.inferredPawnCapture(san: "d6", plyIndex: 4)])
        ]
        for (text, expected) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first)
            let tokens = PGNExporter.tokenText(from: parsed)
            let snapshot = PGNParser.parseMainLineSnapshot(from: parsed)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(parsed.diagnostics, [], text)
            XCTAssertEqual(snapshot.diagnostics, [], text)
            XCTAssertEqual(snapshot.notices, expected, text)
            XCTAssertEqual(report.diagnostics, [], text)
            XCTAssertEqual(report.notices, expected, text)
            XCTAssertEqual(snapshot.moves.map(\.move), report.game.mainLine.map(\.move), text)
            XCTAssertEqual(PGNParser.loadGameWithImputation(from: parsed)?.diagnostics, [], text)
            XCTAssertEqual(PGNParser.loadGameWithImputation(from: parsed)?.notices, expected, text)
            XCTAssertEqual(PGNExporter.tokenText(from: parsed), tokens, text)
            var flat = parsed
            flat.moveTokens = []
            XCTAssertEqual(PGNParser.parseMainLineSnapshot(from: flat).diagnostics, [], text)
            XCTAssertEqual(PGNParser.parseMainLineSnapshot(from: flat).notices, expected, text)
            XCTAssertEqual(PGNParser.loadGameWithReport(from: flat)?.diagnostics, [], text)
            XCTAssertEqual(PGNParser.loadGameWithReport(from: flat)?.notices, expected, text)
        }
    }

    /// Gates warning propagation across branches, prefix limits and failures.
    /// Reusing a main-line counter or discarding accumulated notices could
    /// conceal a guessed move or point users to the wrong move in their game.
    func testInferredCaptureNoticesKeepBranchPlyAndSurviveLaterReplayFailure() throws {
        let branch = try XCTUnwrap(PGNParser.parse("1. e4 (1. d4 e5 2. e5) d5 2. d5").first)
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: branch))
        XCTAssertEqual(report.diagnostics, [])
        XCTAssertEqual(report.notices, [.inferredPawnCapture(san: "e5", plyIndex: 2),
                                            .inferredPawnCapture(san: "d5", plyIndex: 2)])
        XCTAssertEqual(PGNParser.parseMainLineSnapshot(from: branch).notices,
                       [.inferredPawnCapture(san: "d5", plyIndex: 2)])
        XCTAssertTrue(PGNParser.parseMainLineSnapshot(from: branch, pliesLimit: 2).notices.isEmpty)
        let broken = try XCTUnwrap(PGNParser.parse("1. e4 d5 2. d5 Zz9 {open").first)
        let failed = PGNParser.parseMainLineSnapshot(from: broken)
        XCTAssertTrue(failed.moves.isEmpty)
        XCTAssertEqual(failed.diagnostics, [.unterminatedBraceComment,
                                            .unparseableMainlineMove(san: "Zz9", plyIndex: 3)])
        XCTAssertEqual(failed.notices, [.inferredPawnCapture(san: "d5", plyIndex: 2)])
        XCTAssertEqual(PGNParser.loadGameWithReport(from: broken)?.diagnostics,
                       [.unterminatedBraceComment])
        XCTAssertEqual(PGNParser.loadGameWithReport(from: broken)?.notices,
                       [.inferredPawnCapture(san: "d5", plyIndex: 2)])
    }

    /// Captured from 0.17.1: the guessed capture remains usable downstream.
    func test0171LiteralInferredCaptureGoldenKeepsDiagnosticsAndGame() throws {
        let parsed = try XCTUnwrap(PGNParser.parse("1. e4 d5 2. d5").first)
        let snapshot = PGNParser.parseMainLineSnapshot(from: parsed)
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
        let imputed = try XCTUnwrap(PGNParser.loadGameWithImputation(from: parsed))
        XCTAssertEqual(parsed.diagnostics, [])
        XCTAssertEqual(parsed.notices, []) // Lexing does not replay moves.
        for notices in [snapshot.notices, report.notices, imputed.notices] {
            XCTAssertEqual(notices, [.inferredPawnCapture(san: "d5", plyIndex: 2)])
        }
        XCTAssertEqual(snapshot.diagnostics, [])
        XCTAssertEqual(report.diagnostics, [])
        XCTAssertEqual(imputed.diagnostics, [])
        XCTAssertEqual(parsed.moves, ["e4", "d5", "d5"])
        XCTAssertEqual(PGNExporter.tokenText(from: parsed), "e4 d5 d5")
        XCTAssertEqual(snapshot.moves.map { $0.move.uci }, ["e2e4", "d7d5", "e4d5"])
        XCTAssertEqual(snapshot.moves.last?.positionAfter.fen,
                       "rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2")
        for game in [report.game, imputed.game, try XCTUnwrap(PGNParser.loadGame(from: parsed)),
                     try PGNParser.loadGame(from: parsed, maximumTreeNodes: 10)] {
            XCTAssertEqual(game.mainLine.map { $0.move.uci }, ["e2e4", "d7d5", "e4d5"])
            XCTAssertEqual(PGNExporter.moveText(for: game.rootChildren), "1. e4 d5 2. exd5")
            XCTAssertEqual(game.position.fen, snapshot.moves.last?.positionAfter.fen)
        }
        // These flags were already false in 0.17.1, independently of notices.
        XCTAssertFalse(report.canReplaceStoredText)
        XCTAssertFalse(report.canReplaceStoredTextKeepingLeadingComments)
    }

    func testCarriedNoticesSurviveInvalidFENAndImputationWithoutAffectingCleanFlags() throws {
        var parsed = try XCTUnwrap(PGNParser.parse("1. e4 d5 2. Pd5").first)
        let notice = PGNLoadNotice.inferredPawnCapture(san: "prior", plyIndex: 8)
        parsed.notices = [notice]
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
        XCTAssertEqual(report.notices, [notice, .inferredPawnCapture(san: "Pd5", plyIndex: 2)])
        XCTAssertEqual(PGNParser.loadGameWithImputation(from: parsed)?.notices, report.notices)
        XCTAssertEqual(PGNParser.parseMainLineSnapshot(from: parsed).notices, report.notices)
        // Explicit P was accepted cleanly by 0.17.1. A notice cannot change that.
        XCTAssertTrue(report.canReplaceStoredText)
        XCTAssertTrue(report.canReplaceStoredTextKeepingLeadingComments)
        parsed.tags["FEN"] = "invalid"
        let invalid = PGNParser.parseMainLineSnapshot(from: parsed)
        XCTAssertEqual(invalid.diagnostics, [.invalidFEN("invalid")])
        XCTAssertEqual(invalid.notices, [notice])
    }

    func testInferredCaptureRemainsReadableButCannotRewriteAndChangeStoredIdentity() throws {
        let cases: [(String, String, Bool, [String])] = [
            ("1. e4 d5 2. d5", "1. e4 d5 2. exd5", false, ["d5"]),
            ("1. e4 d5 2. ed5", "1. e4 d5 2. exd5", true, []),
            ("1. e4 d5 2. exd5", "1. e4 d5 2. exd5", true, []),
            ("1. e2e4", "1. e4", true, []),
            ("1. e4 d5 2. d5!", "1. e4 d5 2. exd5!", false, ["d5!"]),
            ("1. e4 ( 1. d4 e5 2. e5 ) d5", "1. e4 ( 1. d4 e5 2. dxe5 ) d5", false, ["e5"])
        ]
        for (text, tree, eligible, uncarried) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first, text)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed), text)
            XCTAssertEqual(PGNExporter.moveText(for: report.game.rootChildren), tree, text)
            XCTAssertTrue(report.droppedMoveTokens.isEmpty, text)
            XCTAssertEqual(report.uncarriedText, uncarried, text)
            XCTAssertEqual(report.canReplaceStoredText, eligible, text)
            XCTAssertEqual(report.canReplaceStoredTextKeepingLeadingComments, eligible, text)
        }

        var flat = PGNGame()
        flat.moves = ["e4", "d5", "d5"]
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: flat))
        XCTAssertEqual(PGNExporter.moveText(for: report.game.rootChildren), "1. e4 d5 2. exd5")
        XCTAssertEqual(report.uncarriedText, ["d5"])
        XCTAssertFalse(report.canReplaceStoredText)
    }
}
