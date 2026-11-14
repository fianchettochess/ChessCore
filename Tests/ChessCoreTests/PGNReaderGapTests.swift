import XCTest
@testable import ChessCore

final class PGNReaderGapTests: XCTestCase {
    /// Gates replay normalization, which could swallow a real variation or
    /// shift its token offsets. The user must keep the promotion, annotations,
    /// and subsequent branches while the stored lexical identity stays fixed.
    func testPromotionDialectsKeepMovesAndLegacyTokensSoStoredGamesKeepTheirIdentity() throws {
        let fen = "7k/P7/8/8/8/8/1p6/4K3 w - - 0 23"
        let cases: [(String, String)] = [
            ("a8=q", "a8=q"), ("a8/Q", "a8/Q"), ("a8Q", "a8Q"),
            ("a8(Q)", "a8 ( Q )"), ("a8(n)", "a8 ( n )")
        ]
        for (word, lexical) in cases {
            let text = "[FEN \"\(fen)\"]\n23. \(word) {promoted} Kh7 (23... Kg7) *"
            let parsed = try XCTUnwrap(PGNParser.parse(text).first)
            XCTAssertEqual(PGNExporter.tokenText(from: parsed), lexical + " {promoted} Kh7 ( Kg7 )", word)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(report.game.mainLine.count, 2, word)
            XCTAssertEqual(report.game.mainLine.first?.move.promotion, word == "a8(n)" ? .knight : .queen, word)
            XCTAssertEqual(report.game.mainLine.first?.comment, "promoted", word)
            XCTAssertEqual(report.game.rootChildren.first?.children.map(\.notation), ["Kh7", "Kg7"], word)
            XCTAssertTrue(report.droppedMoveTokens.isEmpty, word)
            XCTAssertFalse(report.mainLineDiffersFromSnapshot, word)
            if word != "a8Q" { XCTAssertFalse(report.canReplaceStoredText, word) }
            let snapshot = PGNParser.parseMainLineSnapshot(from: parsed)
            XCTAssertEqual(snapshot.moves.map(\.move), report.game.mainLine.map(\.move), word)
            XCTAssertEqual(report.diagnostics, [], word)
            if word == "a8(Q)" || word == "a8(n)" {
                XCTAssertEqual(snapshot.diagnostics, [.unparseableMainlineMove(san: "a8", plyIndex: 0)], word)
            } else {
                XCTAssertEqual(snapshot.diagnostics, [], word)
            }
            let strict = try PGNParser.loadGame(from: parsed, maximumTreeNodes: 20)
            XCTAssertEqual(strict.mainLine.map(\.move), report.game.mainLine.map(\.move), word)
            let imputation = try XCTUnwrap(PGNParser.loadGameWithImputation(from: parsed))
            XCTAssertTrue(imputation.imputedMoves.isEmpty, word)
            XCTAssertEqual(imputation.game.mainLine.map(\.move), report.game.mainLine.map(\.move), word)
            XCTAssertEqual(PGNExporter.tokenText(from: parsed), lexical + " {promoted} Kh7 ( Kg7 )", word)
        }
        let position = try XCTUnwrap(Position(fen: fen))
        XCTAssertNotNil(PGNParser.parseMoveWord("a8(Q)", in: position))
        XCTAssertNil(PGNParser.parseMove("a8(Q)", in: position))
        var flat = PGNGame()
        flat.tags["FEN"] = fen
        flat.moves = ["a8(Q)", "Kh7"]
        XCTAssertEqual(PGNParser.loadGameWithReport(from: flat)?.game.mainLine.count, 2)
    }

    /// Gates the shape check and variation-offset remapping: a broad rewrite
    /// could turn an ordinary branch into a promotion, losing the user's line.
    func testParenthesizedPromotionRepairKeepsRealVariationsAndRejectsInvalidPieceWords() throws {
        let fen = "7k/P7/8/8/8/8/1p6/4K3 w - - 0 23"
        let cases = [
            "[FEN \"\(fen)\"]\n23. a8(Q) Kh7 (23... Kg7 (23... Kh7))",
            "[FEN \"\(fen)\"]\n23. Kd2 (23. a8(Q) Kh7) b1=Q",
            "[FEN \"\(fen)\"]\n23. a8(Q) Kh7 (23... Kg7) 24. Qh1 (24. Qa7)"
        ]
        for text in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            let canonical = text.replacingOccurrences(of: "a8(Q)", with: "a8=Q")
            let reference = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(canonical).first)))
            XCTAssertEqual(PGNExporter.moveText(for: report.game.rootChildren), PGNExporter.moveText(for: reference.game.rootChildren), text)
            XCTAssertEqual(report.variationOrder, reference.variationOrder, text)
            XCTAssertEqual(report.hasUncertainVariationPlacement, reference.hasUncertainVariationPlacement, text)
            XCTAssertTrue(report.droppedMoveTokens.isEmpty, text)
        }
        for word in ["a8(K)", "a8(QQ)", "a8(Q e5)"] {
            let parsed = try XCTUnwrap(PGNParser.parse("[FEN \"\(fen)\"]\n23. \(word)").first)
            XCTAssertFalse(try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed)).droppedMoveTokens.isEmpty, word)
        }
        let ordinary = try XCTUnwrap(PGNParser.parse("1. e4 (1. d4 d5 2. c4) e5").first)
        XCTAssertEqual(PGNExporter.moveText(for: try XCTUnwrap(PGNParser.loadGame(from: ordinary)).rootChildren), "1. e4 ( 1. d4 d5 2. c4 ) e5")
    }

    /// Gates both null spellings on every replay route. Treating them as noise
    /// or a pass could silently put the user's later moves on the wrong board.
    func testNullMovesRemainRejectedAndReportedWithoutClosingStoredGames() throws {
        for word in ["--", "Z0"] {
            let parsed = try XCTUnwrap(PGNParser.parse("1. e4 \(word) 2. d4 Nf6 *").first)
            let expected = PGNDiagnostic.unparseableMainlineMove(san: word, plyIndex: 1)
            XCTAssertTrue(PGNParser.parseMainLineSnapshot(from: parsed).diagnostics.contains(expected), word)
            XCTAssertThrowsError(try PGNParser.loadGame(from: parsed, maximumTreeNodes: 20)) {
                XCTAssertEqual($0 as? PGNDiagnostic, expected)
            }
            XCTAssertEqual(PGNParser.loadGameWithReport(from: parsed)?.droppedMoveTokens, [word, "d4"])
            XCTAssertNotNil(PGNParser.loadGame(from: parsed))
            let branch = try XCTUnwrap(PGNParser.parse("1. e4 (1. d4 \(word) 2. c4) e5").first)
            XCTAssertEqual(PGNParser.loadGameWithReport(from: branch)?.droppedMoveTokens, [word, "c4"])
            XCTAssertNil(PGNParser.parseMove(word, in: .initial()))
        }
    }

    /// Gates the convenience parser's loss signal. Returning only the next
    /// record after a resource overflow could display or save the wrong game.
    func testConvenienceParsingReportsSkippedRecordsWithoutChangingSurvivingGames() throws {
        let big = "[Event \"Big\"]\n1.e4 {" + String(repeating: "x", count: 40) + "} e5 *"
        let good = "[Event \"Good\"]\n1.d4 d5 *"
        let cases: [(String, Int, Bool)] = [(big + "\n" + good, 1, true),
                                          (good + "\n" + big, 1, false),
                                          (big + "\n" + good + "\n" + big, 2, true)]
        for (text, count, beforeFirst) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text, maximumMoveTextBytes: 24).first)
            XCTAssertEqual(parsed.event, "Good")
            XCTAssertEqual(parsed.moves, ["d4", "d5"])
            XCTAssertEqual(parsed.recordDiagnostics, [.oversizedRecordsSkipped(count: count, beforeFirstGame: beforeFirst)])
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(report.oversizedRecordsSkipped, count)
            XCTAssertFalse(report.canReplaceStoredText)
            XCTAssertFalse(report.canReplaceStoredTextKeepingLeadingComments)
            XCTAssertEqual(PGNParser.loadGameWithImputation(from: parsed)?.oversizedRecordsSkipped, count)
        }
    }
}
