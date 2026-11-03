import XCTest
@testable import ChessCore

final class PGNAttachedNotationTests: XCTestCase {
    func testAttachedNotationReadsFullGameButCannotRewriteChangedWords() throws {
        var cases: [(String, String)] = [
            ("1. e4 ...e5 2. Nf3", "1. e4 e5 2. Nf3"),
            ("1. e4 1…e5 2. Nf3", "1. e4 e5 2. Nf3"),
            ("1. e4 …e5 2. Nf3", "1. e4 e5 2. Nf3"),
            ("1.e4$1 e5$2 2.Nf3", "1. e4! e5? 2. Nf3"),
            ("1. e4!$1 e5", "1. e4! e5"),
            ("1. e4 ( 1. d4 ...d5 2. c4 ) e5", "1. e4 ( 1. d4 d5 2. c4 ) e5")
        ]
        for glyph in ["+-", "+=", "=+", "-+", "+/-", "-/+", "∞", "±"] {
            cases.append(("1. e4 e5 2. Nf3\(glyph) Nc6", "1. e4 e5 2. Nf3 Nc6"))
        }
        for (text, expected) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(PGNExporter.moveText(for: report.game.rootChildren), expected, text)
            XCTAssertTrue(report.droppedMoveTokens.isEmpty, text)
            XCTAssertFalse(report.canReplaceStoredText, text)
            XCTAssertFalse(report.mainLineDiffersFromSnapshot, text)
            XCTAssertFalse(PGNParser.parseMainLineSnapshot(from: parsed).moves.isEmpty, text)
        }
        for word in ["a8=q", "a8/Q"] {
            let parsed = try XCTUnwrap(PGNParser.parse("[FEN \"8/P7/8/8/8/8/8/k1K5 w - - 0 1\"]\n\n1. \(word)").first)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
            XCTAssertEqual(PGNExporter.moveText(for: report.game.rootChildren), "1. a8=Q#")
            XCTAssertFalse(report.canReplaceStoredText)
        }
    }

    func testIncompleteNotationStillDropsMovesSoCorruptionIsNotHidden() throws {
        for text in ["1. e4 e5 2. Nf3= Nc6", "e8=", "e4 e5 2. Nf3-", "1. e4 (1. d4 -- 2. c4) e5", "[FEN \"8/P7/8/8/8/8/8/k1K5 w - - 0 1\"]\n\n1. a8(Q)"] {
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(text).first)))
            XCTAssertFalse(report.droppedMoveTokens.isEmpty, text)
            XCTAssertFalse(report.canReplaceStoredText, text)
        }
    }

    func testAllReplayRoutesReadAttachedWordsSoMovesAndRepairsSurvive() throws {
        let parsed = try XCTUnwrap(PGNParser.parse("1. e4 ...e5 2. Nf3 Nc6").first)
        let snapshot = PGNParser.parseMainLineSnapshot(from: parsed)
        XCTAssertEqual(snapshot.moves.map(\.notation), ["e4", "e5", "Nf3", "Nc6"])
        let report = try XCTUnwrap(PGNParser.loadGameWithImputation(from: parsed))
        XCTAssertTrue(report.imputedMoves.isEmpty)
        XCTAssertFalse(report.mainLineDiffersFromSnapshot)
        XCTAssertEqual(report.game.mainLine.map(\.notation), ["e4", "e5", "Nf3", "Nc6"])
        let repair = try XCTUnwrap(PGNParser.parse("1. d4 Zz8 2. Nf3 ...e4").first)
        XCTAssertEqual(try XCTUnwrap(PGNParser.loadGameWithImputation(from: repair)).imputedMoves.map(\.notation), ["e5"])
        let afterAttached = try XCTUnwrap(PGNParser.parse("1. ...d4 Zz8 2. Nf3 e4").first)
        XCTAssertEqual(try XCTUnwrap(PGNParser.loadGameWithImputation(from: afterAttached)).imputedMoves.map(\.notation), ["e5"])
        let oldOrder = try XCTUnwrap(PGNParser.parse("1. e4 ...e5 2. Nf3 ( 2. Bc4 ( 2... Bc5 3. c3 ) ( 2... d6 ) 2... Nf6 3. d3 ) Nc6").first)
        let oldReport = try XCTUnwrap(PGNParser.loadGameWithReport(from: oldOrder))
        XCTAssertEqual(oldReport.variationOrder, .alternativesBeforeContinuation)
        XCTAssertTrue(oldReport.droppedMoveTokens.isEmpty)
        var flat = PGNGame()
        flat.moves = ["e4$1", "...e5", "Nf3"]
        let flatReport = try XCTUnwrap(PGNParser.loadGameWithReport(from: flat))
        XCTAssertEqual(flatReport.game.mainLine.map(\.notation), ["e4", "e5", "Nf3"])
        XCTAssertFalse(flatReport.canReplaceStoredText)
        XCTAssertEqual(PGNExporter.moveText(for: flatReport.game.rootChildren), "1. e4! e5 2. Nf3")
        var legacyFlat = PGNGame()
        legacyFlat.moves = ["e4!"]
        let legacy = try XCTUnwrap(PGNParser.loadGameWithReport(from: legacyFlat))
        XCTAssertNil(legacy.game.mainLine.first?.annotation)
        XCTAssertNotNil(PGNParser.parseMoveWord("...e4", in: Position.initial()))
        XCTAssertNil(PGNParser.parseMove("...e4", in: Position.initial()))
    }

    func testLegalSANAndAnnotationsStayUnchangedSoExistingReadingsSurvive() {
        var position = Position.initial()
        for _ in 0..<80 {
            let legal = MoveGenerator.legalMoves(for: position)
            guard !legal.isEmpty else { break }
            for move in legal {
                let san = MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: legal)
                for suffix in ["", "!", "??", "!?"] {
                    let word = san + suffix
                    let read = PGNParser.readableMoveWord(word)
                    XCTAssertEqual(read.san, word)
                    XCTAssertFalse(read.altered)
                }
            }
            MoveGenerator.applyMoveUnchecked(&position, legal[(position.fullmoveNumber * 13) % legal.count])
        }
    }
}
