import XCTest
@testable import ChessCore

final class PGNUncarriedTextTests: XCTestCase {
    func testStoredTextCases() throws {
        let cases: [(String, Bool)] = [
            ("1. e4 {[%eval +0.34]; best Nf3} e5 {[%eval -0.12]; best Nc6}", true),
            ("1. e4 {+0.34; best Nf3} e5 {-0.12; best Nc6}", true),
            ("1. e4 {+0.3; best Nf3} e5 {M; best Nc6}", true),
            ("1. e4?? {[%clk 0:03:00] [%eval +0.34]; best d4; my note} e5! {[%eval #3]; best Nc6} 2. Nf3?! {-M}", true),
            ("1. e4 {+0.34;\nbest Nf3} e5", true),
            ("1. e4 {[%clk 0:03:00]} 1... c5 {[%clk 0:03:00]}", true),
            ("1. e4 { [%eval 0.17] [%clk 0:00:30] } 1... c5 {...} 2. Nf3?! { [%eval -0.4] [%clk 0:00:29] }", true),
            ("{ Chapter intro. } 1. e4 e5 2. Nf3 $1 { Developing. } 2... Nc6", false),
            ("1. e4 $1 { [%csl Gd4][%cal Gd4e5] Good } 1... e5 $14 { equal-ish } 2. Nf3 $146 ( 2. f4 $5 { gambit } 2... exf4 $16 ) 2... Nc6", false),
            ("1. e4 { [%cal Ge2e4] } 1... e5 $32 $36 { initiative } 2. Nf3 $132", false),
            ("1. e4 $1 $14 { both } 1... e5 $2 $18", false),
            ("1. e4 $1 { Good } e5 $2 { Bad }", true),
            ("1. e4 ( 1. d4 { queen pawn } 1... d5 ) 1... e5", true),
            ("1. e4 e5 ( { Better is } 1... c5 { Sicilian } 2. Nf3 ) 2. Nf3", true),
            ("1. e4 ( { or } 1. d4 ) e5", false),
            ("1. e4 e5 2. Nf3 ( { Or } 2. f4 ) ( $5 2. Bc4 ) 2... Nc6", false),
            ("{ [%evp 0,3,12,14] } 1. e4 e5", false),
            ("1. e4 e5 { (+0.2) } 2. Nf3 $5 { [%emt 0:00:12] }", true),
            ("{Important intro} 1. e4 e5", false), ("1. e4 $14 e5 $10", false),
            ("1. e4 e5 (1... c5 {keep me} 2 {also me}) 2. Nf3", false),
            ("1. e4 e5\n; best d4 e5 2. Nf3\n2. Nf3", false),
            ("; best d4 e5 2. Nf3\n1. e4 e5", false),
            ("1. e4 {best d4 e5 2. Nf3} e5", false), ("1. e4 {Plan; best d4 e5} e5", false),
            ("1. e4 {best play} e5", false), ("1. e4 e5 ( {+0.9} 1... c5 ) 2. Nf3", false),
            ("1. e4 e5 ( {why} 1... c5 ) 2. Nf3", true),
            ("1. e4 e5 ( {see Nf3 note} ) 2. Nf3", true),
            ("1. e4 ( {a} ( {b} 1. d4 ) 1. c4 ) e5", false),
            ("1. e4! (1. e4?) e5", false), ("1. e4 $1 $6 e5", false),
            ("1. e4 e5 ( $14 1... c5 ) 2. Nf3", false), ("1. e4 e5 ( $1 1... c5 ) 2. Nf3", false),
            ("1. e4 {0-1} e5", false), ("1. e4 {0-0} e5", false), ("1. e4 {+1} e5", false),
            ("1. e4 {0-0 is coming} e5", true), ("1. e4 {+-} e5", true),
            ("1. e4 {+0.5} e5", true), ("1. e4 {M} e5", true), ("1. e4 {best Nf3} e5", true),
            ("1. e4 {+0.1; +0.2} e5", false), ("1. e4 {best Nf3; best d4} e5", false),
            ("1. e4 {+0.1} {+0.2} e5", false),
            ("1. e4 {[%clk 0:03:00]} {[%clk 0:02:00]} e5", false),
            ("1. e4 {[%eval 0.1] [%eval 0.2]} e5", false),
            ("1. e4 {[%clk 99999:00:00] note} e5", false), ("1. e4 {a} {b} e5", true),
            ("1. e4 e5 2. Nf3 N Nc6 3. Bb5", false), ("1. e4 += e5", false),
            ("1. e4 e5 +- 2. Nf3", false), ("1. e4 ! e5", false), ("$1 1. e4 e5", false),
            ("1. e4 + e5", true), ("1. e4 ... e5", true), ("1. e4 e5 2. Nf3 e.p. Nc6", true),
            ("1. e4+= e5", false), ("{only}", false), ("1. e4 {[%clk 0:03:00] M} e5", true),
            ("1. e4 {[%clk 0:03:00] [%clk 0:03:00]} e5", false),
            ("1. e4 {best Nf3} {best d4} e5", false),
            ("1. e4 e5 (1... Zz9 {lost}) 2. Nf3", false),
            ("1. e4 e5 (1... Zz9 $1) 2. Nf3", false)
        ]
        let taggedWriterRows: [(String, Bool)] = [
            ("1. e4!? {[%clk 0:03:00] [%eval +1.34]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval +1.34]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n+1.34]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval +1.34]; best Nc6;\nauthored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] [%eval -0.21]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval -0.21]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n-0.21]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval -0.21]; best Nc6;\nauthored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] [%eval +0.3]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval +0.3]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n+0.3]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval +0.3]; best Nc6;\nauthored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] M; best Nf3; authored note} e5!? {[%clk 0:03:00] M; best\nNc6; authored note} 2. Nf3!? {[%clk 0:03:00] M; best Nf3; authored note} Nc6!?\n{[%clk 0:03:00] M; best Nc6; authored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] -M; best Nf3; authored note} e5!? {[%clk 0:03:00] -M;\nbest Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] -M; best Nf3; authored note}\nNc6!? {[%clk 0:03:00] -M; best Nc6; authored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] [%eval #5]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval #5]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n#5]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval #5]; best Nc6;\nauthored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] [%eval #-3]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval #-3]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n#-3]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval #-3]; best Nc6;\nauthored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] [%eval 0.00]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval 0.00]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n0.00]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval 0.00]; best Nc6;\nauthored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] [%eval +12.34]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval +12.34]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00]\n[%eval +12.34]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval +12.34];\nbest Nc6; authored note} *", true), // 0.11.4
            ("1. e4!? {[%clk 0:03:00] [%eval +1.34]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval +1.34]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n+1.34]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval +1.34]; best Nc6;\nauthored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] [%eval -0.21]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval -0.21]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n-0.21]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval -0.21]; best Nc6;\nauthored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] [%eval +0.3]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval +0.3]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n+0.3]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval +0.3]; best Nc6;\nauthored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] M; best Nf3; authored note} e5!? {[%clk 0:03:00] M; best\nNc6; authored note} 2. Nf3!? {[%clk 0:03:00] M; best Nf3; authored note} Nc6!?\n{[%clk 0:03:00] M; best Nc6; authored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] -M; best Nf3; authored note} e5!? {[%clk 0:03:00] -M;\nbest Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] -M; best Nf3; authored note}\nNc6!? {[%clk 0:03:00] -M; best Nc6; authored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] [%eval #5]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval #5]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n#5]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval #5]; best Nc6;\nauthored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] [%eval #-3]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval #-3]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n#-3]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval #-3]; best Nc6;\nauthored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] [%eval 0.00]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval 0.00]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00] [%eval\n0.00]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval 0.00]; best Nc6;\nauthored note} *", true), // 0.13.2
            ("1. e4!? {[%clk 0:03:00] [%eval +12.34]; best Nf3; authored note} e5!? {[%clk\n0:03:00] [%eval +12.34]; best Nc6; authored note} 2. Nf3!? {[%clk 0:03:00]\n[%eval +12.34]; best Nf3; authored note} Nc6!? {[%clk 0:03:00] [%eval +12.34];\nbest Nc6; authored note} *", true), // 0.13.2
        ]
        for (text, expected) in cases + taggedWriterRows {
            let scan = PGNParser.tokenizeWithVariationDiagnostics(text)
            var input = PGNGame()
            input.moveTokens = scan.tokens
            input.diagnostics = scan.diagnostics
            input.variationWrittenOffsets = scan.variationWrittenOffsets
            input.hasInconsistentMoveNumbers = scan.hasInconsistentMoveNumbers
            let report = try XCTUnwrap(PGNParser.loadGameWithReport(from: input), text)
            XCTAssertEqual(report.canReplaceStoredText, expected, text)
            if text.contains("Zz9 {lost}") { XCTAssertTrue(report.uncarriedText.contains("lost"), text) }
            if text.contains("Zz9 $1") { XCTAssertTrue(report.uncarriedText.contains("$1"), text) }
            if text.contains("{why}") { XCTAssertEqual(report.headCommentsMovedToBranchPoint, 1, text) }
            if expected {
                let prose = scan.tokens.flatMap { token -> [String] in
                    guard case .comment(let text) = token,
                          let comment = PGNParser.parseEngineComment(text).comment else { return [] }
                    return comment.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                }
                func simulatePass(_ nodes: [MoveNode]) {
                    for node in nodes {
                        node.engineEval = nil
                        node.engineBestMoveUCI = nil
                        node.annotation = nil
                        simulatePass(node.children)
                    }
                }
                simulatePass(report.game.rootChildren)
                let exported = PGNExporter.export(game: report.game)
                let outputComments = PGNParser.tokenizeWithVariationDiagnostics(exported).tokens.compactMap { token -> String? in
                    guard case .comment(let text) = token else { return nil }
                    return text
                }.joined(separator: " ")
                for word in prose { XCTAssertTrue(outputComments.contains(word), "missing \(word): \(text)") }
                let reloaded = try XCTUnwrap(PGNParser.loadGame(from: exported), text)
                XCTAssertEqual(try GameTreeSnapshot(capturing: report.game), try GameTreeSnapshot(capturing: reloaded), text)
            }
        }
    }
}
