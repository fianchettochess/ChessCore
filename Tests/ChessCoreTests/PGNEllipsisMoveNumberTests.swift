import XCTest
@testable import ChessCore

final class PGNEllipsisMoveNumberTests: XCTestCase {
    func testEllipsisPositionsGateRewritesSoIncorrectNumbersDoNotReplaceGames() throws {
        let cases: [(String, Bool, Bool, [String])] = [
            ("1. e4 1… e5 2. Nf3", false, false, ["1…"]),
            ("1. e4 1.. e5 2. Nf3", false, true, []),
            ("1. e4 1..e5 2. Nf3", false, true, []),
            ("1. e4 2… e5", true, false, ["2…"]),
            ("1. e4 e5 2.. Nf3 Nc6", true, false, [])
        ]
        for (text, inconsistent, eligible, uncarried) in cases {
            let parsed = try XCTUnwrap(PGNParser.parse(text).first, text)
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed), text)
            XCTAssertEqual(parsed.hasInconsistentMoveNumbers, inconsistent, text)
            XCTAssertEqual(report.canReplaceStoredText, eligible, text)
            XCTAssertEqual(report.uncarriedText, uncarried, text)
        }
        XCTAssertEqual(PGNParser.tokenize("1. e4 1.. e5 2. Nf3").map { String(describing: $0) }, PGNParser.tokenize("1. e4 1... e5 2. Nf3").map { String(describing: $0) })
        XCTAssertEqual(PGNParser.tokenize("1. e4 1..e5 2. Nf3").map { String(describing: $0) }, PGNParser.tokenize("1. e4 1...e5 2. Nf3").map { String(describing: $0) })
    }

    func testNestedTwoDotOffsetCanAllowRewriteWithDifferentTokensSoIdentityMustBeChecked() throws {
        // A corpus row, with the black move number changed from three dots to two.
        let text = "1. e4 f5 2. Ne2 a6 3. b3 Nf6 4. c3 Nc6 ( 4.. a5 {note note} ( 5. e5 f4 ) 5. Na3 b6 6. g3 ) ( 4... c5 5. f3 ) ( 4... Kf7 ) 5. g4 b5 6. Ng1 ( 6. h4 d6 ) b4 ( 6... Nb8 ) ( 6... Rg8 {note} )"
        let parsed = try XCTUnwrap(PGNParser.parse(text).first)
        let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: parsed))
        XCTAssertTrue(report.canReplaceStoredText)
        let exported = PGNExporter.moveText(for: report.game.rootChildren)
        XCTAssertNotEqual(PGNParser.tokenize(text).map { String(describing: $0) }, PGNParser.tokenize(exported).map { String(describing: $0) })
    }
}
