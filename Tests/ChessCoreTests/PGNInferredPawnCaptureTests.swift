import XCTest
@testable import ChessCore

final class PGNInferredPawnCaptureTests: XCTestCase {
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
