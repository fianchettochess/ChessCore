import XCTest
@testable import ChessCore

/// Saved library games persist only their PGN movetext, so a nested analysis
/// line has to survive export and re-import in its original place.
final class PGNNestedVariationTests: XCTestCase {

    private func tree(_ movetext: String) throws -> GameTreeSnapshot {
        let game = try XCTUnwrap(PGNParser.loadGame(from: movetext))
        return try GameTreeSnapshot(capturing: game)
    }

    func testNestedVariationsRoundTripAtDepthsTwoAndThree() throws {
        let cases = [
            "1. e4 e5 2. Nf3 ( 2. Bc4 Nf6 ( 2... Bc5 3. c3 ) 3. d3 ) 2... Nc6 *",
            "1. e4 e5 2. Nf3 ( 2. Bc4 Nf6 ( 2... Bc5 3. c3 ( 3. Nf3 d6 ) 3... d6 ) ( 2... Nc6 3. Nf3 ) 3. d3 ) 2... Nc6 3. Bb5 *",
            "1. e4 e5 2. Nf3 ( 2. Bc4 $1 { develops } Nf6 ( 2... Bc5 { solid } 3. c3 ) 3. d3 ) 2... Nc6 *",
            // Nd4 is legal for either side, and must keep its standard reading.
            "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3. Nd4 ) 3... e6 ) 1... e5 *",
            // Written after e6 instead of e3, Nd4 would replay as a black move.
            "1. e4 ( 1. Nf3 Nc6 2. Nc3 e6 3. e3 ( 3. Nd4 ) ) 1... e5 *",
        ]
        for movetext in cases {
            let original = try XCTUnwrap(PGNParser.loadGame(from: movetext))
            let firstExport = original.exportPGN()
            let reloaded = try XCTUnwrap(PGNParser.loadGame(from: firstExport))

            XCTAssertEqual(reloaded.exportPGN(), firstExport, movetext)
            XCTAssertEqual(
                try GameTreeSnapshot(capturing: reloaded),
                try GameTreeSnapshot(capturing: original),
                movetext
            )
        }
    }

    func testOldExporterOrderLoadsAsTheTreeItWasWrittenFrom() throws {
        let intended = "1. e4 e5 2. Nf3 ( 2. Bc4 Nf6 ( 2... Bc5 3. c3 ) ( 2... d6 ) 3. d3 ) 2... Nc6 *"
        // The same tree as stored by exporters that wrote a line's
        // alternatives ahead of the move they replace.
        let stored = "1. e4 e5 2. Nf3 ( 2. Bc4 ( 2... Bc5 3. c3 ) ( 2... d6 ) 2... Nf6 3. d3 ) Nc6"

        XCTAssertEqual(try tree(stored), try tree(intended))
    }

    func testOldExporterOrderIsRecognisedWhenTheFirstMoveIsLegalForBothSides() throws {
        // Both sides can play Nd4 here, so only exd4 shows where the line starts.
        let intended = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 e6 ( 3... Nd4 4. exd4 ) 4. d4 ) 1... e5 *"
        let stored = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4 4. exd4 ) 3... e6 4. d4 ) e5"

        XCTAssertEqual(try tree(stored), try tree(intended))
    }
}

extension PGNNestedVariationTests {
    func testWrittenOrdersAndRefusals() throws {
        let old = "1. Nh3 ( 1. b3 {note} g5 ( 2. e3 e6 ) ( 2. b4 ( 2... g4 ) 2... c5 ) ( 2. d4 d5 3. h4 ) 2. Nc3 b5 3. e3 ) b5"
        let intended = "1. Nh3 ( 1. b3 {note} g5 2. Nc3 ( 2. e3 e6 ) ( 2. b4 c5 ( 2... g4 ) ) ( 2. d4 d5 3. h4 ) 2... b5 3. e3 ) 1... b5"
        let oldNd4 = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4 ) 3... e6 4. d3 ) e5"
        let standardNd4 = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3. Nd4 ) 3... e6 ) 1... e5"
        let cases: [(String, String, Bool, PGNVariationOrder)] = [
            (old, intended, true, .alternativesBeforeContinuation),
            ("Nh3 ( b3 {note} g5 ( e3 e6 ) ( b4 ( g4 ) c5 ) ( d4 d5 h4 ) Nc3 b5 e3 ) b5", intended, true, .alternativesBeforeContinuation),
            (oldNd4, "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 e6 ( 3... Nd4 ) 4. d3 ) e5", true, .alternativesBeforeContinuation),
            (standardNd4, standardNd4, true, .standard),
            ("e4 ( Nf3 Nf6 Nc3 Nc6 e3 ( Nd4 ) e6 d3 ) e5", "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3. Nd4 ) 3... e6 4. d3 ) e5", false, .standard),
            ("1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4 ) ) e5", "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3. Nd4 ) ) e5", false, .standard),
            ("1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4 ) 3... e6 ( 3... a6 ) 4. d3 ) e5", "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3. Nd4 ) 3... e6 ( 3... a6 ) 4. d3 ) e5", false, .standard),
            ("1. e4 ( 1. Nf3 ( {see notes} ) Nf6 ) e5", "1. e4 ( 1. Nf3 ( {see notes} ) Nf6 ) e5", true, .standard),
            ("1. e4 ( 1. Nf3 ( ) Nf6 ) e5", "1. e4 ( 1. Nf3 ( ) Nf6 ) e5", true, .standard),
        ]
        for (text, expected, pass, order) in cases {
            let input = try XCTUnwrap(PGNParser.parse(text).first)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: input))
            XCTAssertEqual(try GameTreeSnapshot(capturing: report.game), try tree(expected), text)
            XCTAssertEqual(report.canReplaceStoredText, pass, text)
            XCTAssertEqual(report.variationOrder, order, text)
            let scan = PGNParser.tokenizeWithVariationDiagnostics(text)
            XCTAssertEqual(scan.variationWrittenOffsets, input.variationWrittenOffsets, text)
        }
    }

    func testOffsetsAndManualTokenCarrying() throws {
        let cases: [(String, Int?)] = [
            ("1. e4 ( 1. Nf3 Nf6 2. Nc3 ( 2... e6 ) 2... Nc6 ) e5", 1),
            ("10. e4 ( 10. Nf3 Nf6 11. Nc3 ( 11... e6 ) 11... Nc6 ) e5", 1),
            ("1. e4 ( 1. Nf3 Nf6 2. Nc3 ( 2... e6 4. d4 ) 2... Nc6 ) e5", nil),
        ]
        for (text, expected) in cases {
            let scan = PGNParser.tokenizeWithVariationDiagnostics(text)
            let openings = scan.tokens.enumerated().compactMap { index, token in
                if case .variationStart = token { return index }; return nil
            }
            XCTAssertEqual(scan.variationWrittenOffsets[openings[1]], expected, text)
        }
        let text = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4 ) 3... e6 4. d3 ) e5"
        let scanned = PGNParser.tokenizeWithVariationDiagnostics(text)
        var input = PGNGame()
        input.moveTokens = scanned.tokens
        input.diagnostics = scanned.diagnostics
        input.hasInconsistentMoveNumbers = scanned.hasInconsistentMoveNumbers
        input.variationWrittenOffsets = scanned.variationWrittenOffsets
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: input))
        XCTAssertTrue(report.canReplaceStoredText)
        let snapshot = try GameTreeSnapshot(capturing: report.game)
        let nd4 = try XCTUnwrap(snapshot.nodes.first { $0.moveUCI == "c6d4" })
        let parent = try XCTUnwrap(nd4.parentIndex)
        XCTAssertEqual(snapshot.nodes[parent].moveUCI, "e2e3")
        input.variationWrittenOffsets = [:]
        let withoutNumbers = try XCTUnwrap(PGNParser.loadGameWithImputation(from: input))
        XCTAssertTrue(withoutNumbers.hasUncertainVariationPlacement)
        XCTAssertFalse(withoutNumbers.canReplaceStoredText)
    }

    func testReplayBudgetCannotBypassRefusal() throws {
        let text = "e4 ( Nf3 Nf6 Nc3 Nc6 e3 ( Nd4 ) e6 d3 ) e5 Nf3" + String(repeating: " ( d3 )", count: 70_000)
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(text).first)))
        XCTAssertTrue(report.hasUncertainVariationPlacement)
        XCTAssertFalse(report.canReplaceStoredText)
    }

    func testUnreadableUnrelatedLinesAreRefused() throws {
        for text in [
            "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4 ) 3... e6 ) e5 2. Zz9",
            "1. e4 ( 1. Nf3 g5 ( 2. e3 e6 ) 2. Nc3 ) ( 1. Qh5 ) e5"
        ] {
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(text).first)))
            XCTAssertFalse(report.canReplaceStoredText, text)
        }
    }
}

extension PGNNestedVariationTests {
    func testCrashInputsAndWrittenNumbers() throws {
        let cases = [
            "4611686018427387903... e4 e5 Nf3 Nc6 Bc4 Bc5 ( d3 ) *",
            "4611686018427387903. e4 e5 Nf3 Nc6 Bc4 Bc5 ( d3 ) *",
            "4611686018427387903. ... e4 e5 Nf3 Nc6 Bc4 Bc5 ( d3 ) *",
            "e4 ( 4611686018427387903... d4 d5 c4 e6 Nc3 Nf6 ( Nd2 ) Be7 ) e5 *"
        ]
        for text in cases {
            let game = try XCTUnwrap(PGNParser.parse(text).first, text)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: game), text)
            XCTAssertFalse(report.canReplaceStoredText, text)
        }
        let truncated = "1. e4 ( 1. Nf3 Nf6 2. Nc3 Nc6 3. e3 ( 3... Nd4"
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(truncated).first)))
        XCTAssertTrue(report.hasUncertainVariationPlacement)
        XCTAssertFalse(report.canReplaceStoredText)
    }

    func testBareDigitsPreserveReplayDecision() throws {
        let ambiguous = "e4 ( Nf3 Nf6 Nc3 Nc6 e3 ( Nd4 ) e6 d3 ) e5"
        for text in [ambiguous, ambiguous + " 7", ambiguous + " 2 Nf3", ambiguous + " 7 *", "e4 ( Nf3 Nf6 Nc3 Nc6 e3 ( Nd4 ) e6 d3 7 ) e5"] {
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(text).first)))
            XCTAssertTrue(report.hasUncertainVariationPlacement, text)
            XCTAssertFalse(report.canReplaceStoredText, text)
        }
        let old = "Nh3 ( b3 {note} g5 ( e3 e6 ) ( b4 ( g4 ) c5 ) ( d4 d5 h4 ) Nc3 b5 e3 ) b5 7"
        let expected = "1. Nh3 ( 1. b3 {note} g5 2. Nc3 ( 2. e3 e6 ) ( 2. b4 c5 ( 2... g4 ) ) ( 2. d4 d5 3. h4 ) 2... b5 3. e3 ) 1... b5"
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(old).first)))
        XCTAssertTrue(report.canReplaceStoredText)
        XCTAssertEqual(try GameTreeSnapshot(capturing: report.game), try tree(expected))
    }

    func testExcessiveDepthIsRefusedAndDoesNotLoseFollowingMainline() throws {
        let text = "e4 " + String(repeating: "(", count: 10_000) + " d4 " + String(repeating: ")", count: 10_000) + " e5"
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: XCTUnwrap(PGNParser.parse(text).first)))
        XCTAssertFalse(report.canReplaceStoredText)
        XCTAssertTrue(report.hasUncertainVariationPlacement)
        XCTAssertEqual(report.game.mainLine.map(\.notation), ["e4", "e5"])
    }

    func testOriginalDiagnosticsTupleRemainsSourceCompatible() {
        let (tokens, diagnostics, inconsistent) = PGNParser.tokenizeWithDiagnostics("1. e4")
        let function: (String) -> (tokens: [PGNToken], diagnostics: [PGNDiagnostic], hasInconsistentMoveNumbers: Bool) = PGNParser.tokenizeWithDiagnostics
        XCTAssertEqual(tokens.count, 1)
        XCTAssertTrue(diagnostics.isEmpty)
        XCTAssertFalse(inconsistent)
        XCTAssertEqual(function("e4").tokens.count, 1)
    }
}
