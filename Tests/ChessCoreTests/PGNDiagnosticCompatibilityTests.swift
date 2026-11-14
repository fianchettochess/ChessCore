import XCTest
@testable import ChessCore

/// Literal outputs captured by compiling unmodified tag 0.17.1 (06ae8ee).
/// These gate downstream diagnostics.isEmpty consumers and clean rewrite flags.
final class PGNDiagnosticCompatibilityTests: XCTestCase {
    private struct Golden: Decodable {
        let input: String
        let flat: Bool
        let diagnostics: [String]
        let snapshotDiagnostics: [[String]]
        let flags: [Bool]
    }

    func test0171DiagnosticsAndCleanFlagsAcrossTokenAndFlatReplay() throws {
        let cases = try JSONDecoder().decode([Golden].self, from: Data(Self.golden0171.utf8))
        XCTAssertEqual(cases.count, 80)
        for expected in cases {
            var parsed = try XCTUnwrap(PGNParser.parse(expected.input).first)
            if expected.flat { parsed.moveTokens = [] }
            let context = "flat=\(expected.flat): \(expected.input)"
            XCTAssertEqual(parsed.diagnostics.map { String(describing: $0) }, expected.diagnostics, context)
            let report = PGNParser.loadGameWithReport(from: parsed)
            let imputed = PGNParser.loadGameWithImputation(from: parsed)
            for diagnostics in [report?.diagnostics, imputed?.diagnostics].compactMap({ $0 }) {
                XCTAssertEqual(diagnostics.map { String(describing: $0) }, expected.diagnostics, context)
            }
            for (index, limit) in [-1, 0, 1, 2, 3, 100].enumerated() {
                let snapshot = PGNParser.parseMainLineSnapshot(from: parsed, pliesLimit: limit)
                XCTAssertEqual(snapshot.diagnostics.map { String(describing: $0) },
                               expected.snapshotDiagnostics[index], "limit=\(limit): \(context)")
            }
            let flags = [report?.canReplaceStoredText ?? false,
                         report?.canReplaceStoredTextKeepingLeadingComments ?? false,
                         imputed?.canReplaceStoredText ?? false,
                         imputed?.canReplaceStoredTextKeepingLeadingComments ?? false]
            XCTAssertEqual(flags, expected.flags, context)
        }
    }

    func testManuallyConstructedParenthesizedPromotionsKeep0171Diagnostics() throws {
        for flat in [false, true] {
            var parsed = PGNGame()
            parsed.tags["FEN"] = "7k/P7/8/8/8/8/1p6/4K3 w - - 0 23"
            if flat { parsed.moves = ["a8(Q)", "Kh7"] }
            else { parsed.moveTokens = [.move("a8(Q)"), .move("Kh7")] }
            let snapshot = PGNParser.parseMainLineSnapshot(from: parsed)
            XCTAssertEqual(snapshot.diagnostics, [.unparseableMainlineMove(san: "a8(Q)", plyIndex: 0)])
            XCTAssertEqual(snapshot.moves.map { $0.move.uci }, ["a7a8q", "h8h7"])
            XCTAssertEqual(PGNParser.parseMainLineSnapshot(from: parsed, pliesLimit: 0).diagnostics, [])
        }
    }

    /// This exhaustive switch fails to compile if PGNDiagnostic gains a case.
    private func legacyDiagnosticCode(_ diagnostic: PGNDiagnostic) -> Int {
        switch diagnostic {
        case .tagsOnlyRecord: return 0
        case .unterminatedBraceComment: return 1
        case .invalidFEN: return 2
        case .unparseableMainlineMove: return 3
        case .moveTreeNodeLimitExceeded: return 4
        }
    }

    func testDiagnosticCaseSetMatches0171() {
        XCTAssertEqual([PGNDiagnostic.tagsOnlyRecord, .unterminatedBraceComment, .invalidFEN("bad"),
                        .unparseableMainlineMove(san: "bad", plyIndex: 0),
                        .moveTreeNodeLimitExceeded(maximumNodes: 0)].map(legacyDiagnosticCode), [0, 1, 2, 3, 4])
    }

    private static let golden0171 = #"""
[
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[Event \"Club Championship\"]\n[Site \"?\"]\n[Date \"2009.03.14\"]\n[Round \"4\"]\n[White \"Hall, R.\"]\n[Black \"Okafor, T.\"]\n[Result \"1-0\"]\n\n1. e4 $1 c5 2. Nf3 d6 $14 3. d4 cxd4 4. Nxd4 $18 Nf6 5. Nc3 $146 a6 $300\n6. Be3 $99999999999999999999 e5 1-0","snapshotDiagnostics":[[],[],[],[],[],["unparseableMainlineMove(san: \"$99999999999999999999\", plyIndex: 11)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[Event \"Club Championship\"]\n[Site \"?\"]\n[Date \"2009.03.14\"]\n[Round \"4\"]\n[White \"Hall, R.\"]\n[Black \"Okafor, T.\"]\n[Result \"1-0\"]\n\n1. e4 $1 c5 2. Nf3 d6 $14 3. d4 cxd4 4. Nxd4 $18 Nf6 5. Nc3 $146 a6 $300\n6. Be3 $99999999999999999999 e5 1-0","snapshotDiagnostics":[[],[],[],[],[],["unparseableMainlineMove(san: \"$99999999999999999999\", plyIndex: 11)"]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[Result \"*\"]\n\n1. e4 {[%clk 0:03:00] +0.34; best e4; solid} e5 {-1.42; best Nf3} 2. Nf3 {M3} *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[Result \"*\"]\n\n1. e4 {[%clk 0:03:00] +0.34; best e4; solid} e5 {-1.42; best Nf3} 2. Nf3 {M3} *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[Event \"Rated Blitz game\"]\n[Site \"https://lichess.org/Ab12Cd34\"]\n[Date \"2024.03.14\"]\n[White \"Alice\"]\n[Black \"Bob\"]\n[Result \"1/2-1/2\"]\n[TimeControl \"180+2\"]\n\n1. e4 {[%eval 0.22] [%clk 0:03:00]} e5 {[%clk 0:02:59]} 2. Nf3 Nc6 1/2-1/2","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[Event \"Rated Blitz game\"]\n[Site \"https://lichess.org/Ab12Cd34\"]\n[Date \"2024.03.14\"]\n[White \"Alice\"]\n[Black \"Bob\"]\n[Result \"1/2-1/2\"]\n[TimeControl \"180+2\"]\n\n1. e4 {[%eval 0.22] [%clk 0:03:00]} e5 {[%clk 0:02:59]} 2. Nf3 Nc6 1/2-1/2","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[Event \"Live Chess\"]\n[Site \"Chess.com\"]\n[Date \"2023.06.02\"]\n[Round \"-\"]\n[White \"Alice\"]\n[Black \"Bob\"]\n[Result \"1-0\"]\n[Link \"https://www.chess.com/game/live/123456789\"]\n\n1. d4 {[%clk 0:09:58]} d5 2. c4 e6 (2... c6 $1 {Slav}) 3. Nc3 Nf6 1-0","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[Event \"Live Chess\"]\n[Site \"Chess.com\"]\n[Date \"2023.06.02\"]\n[Round \"-\"]\n[White \"Alice\"]\n[Black \"Bob\"]\n[Result \"1-0\"]\n[Link \"https://www.chess.com/game/live/123456789\"]\n\n1. d4 {[%clk 0:09:58]} d5 2. c4 e6 (2... c6 $1 {Slav}) 3. Nc3 Nf6 1-0","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[Event \"City Championship\"]\n[Site \"London\"]\n[Date \"2011.11.05\"]\n[Round \"3\"]\n[White \"Hall, R.\"]\n[Black \"Okafor, T.\"]\n[Result \"*\"]\n[Annotator \"Coach\"]\n\n1. e4 $1 c5 2. Nf3 d6 (2... Nc6 $5 {Alternative} 3. d4) 3. d4 cxd4 4. Nxd4 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[Event \"City Championship\"]\n[Site \"London\"]\n[Date \"2011.11.05\"]\n[Round \"3\"]\n[White \"Hall, R.\"]\n[Black \"Okafor, T.\"]\n[Result \"*\"]\n[Annotator \"Coach\"]\n\n1. e4 $1 c5 2. Nf3 d6 (2... Nc6 $5 {Alternative} 3. d4) 3. d4 cxd4 4. Nxd4 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 (1 d4 d5 2 c4) e5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 (1 d4 d5 2 c4) e5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[Result \"1-0\"]\n\n1. e4 e5 ½-½","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[Result \"1-0\"]\n\n1. e4 e5 ½-½","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 -- 2. d4 Nf6 *","snapshotDiagnostics":[[],[],[],["unparseableMainlineMove(san: \"--\", plyIndex: 1)"],["unparseableMainlineMove(san: \"--\", plyIndex: 1)"],["unparseableMainlineMove(san: \"--\", plyIndex: 1)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4 -- 2. d4 Nf6 *","snapshotDiagnostics":[[],[],[],["unparseableMainlineMove(san: \"--\", plyIndex: 1)"],["unparseableMainlineMove(san: \"--\", plyIndex: 1)"],["unparseableMainlineMove(san: \"--\", plyIndex: 1)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 Z0 2. d4 Nf6 *","snapshotDiagnostics":[[],[],[],["unparseableMainlineMove(san: \"Z0\", plyIndex: 1)"],["unparseableMainlineMove(san: \"Z0\", plyIndex: 1)"],["unparseableMainlineMove(san: \"Z0\", plyIndex: 1)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4 Z0 2. d4 Nf6 *","snapshotDiagnostics":[[],[],[],["unparseableMainlineMove(san: \"Z0\", plyIndex: 1)"],["unparseableMainlineMove(san: \"Z0\", plyIndex: 1)"],["unparseableMainlineMove(san: \"Z0\", plyIndex: 1)"]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[A \"1\"][B \"2\"]\n1. e4 e5 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[A \"1\"][B \"2\"]\n1. e4 e5 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"﻿% encoding note\n[Event \"Imported\"]\n1. e4\n% hidden {\ne5 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"﻿% encoding note\n[Event \"Imported\"]\n1. e4\n% hidden {\ne5 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4$1 1…e5 2. Nf3 Nc6 3. Bb5 ...Nf6+- *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4$1 1…e5 2. Nf3 Nc6 3. Bb5 ...Nf6+- *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 d5 2. d5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4 d5 2. d5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN 8/P7/8/8/8/8/8/k1K5 w - - 0 1]\n1. a8/Q *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN 8/P7/8/8/8/8/8/k1K5 w - - 0 1]\n1. a8/Q *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[FEN \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 23\"]\n23... e5 24. Nf3 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[FEN \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 23\"]\n23... e5 24. Nf3 *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 e5\n[diagram]\n2. Nf3 Nc6","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4 e5\n[diagram]\n2. Nf3 Nc6","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"1. e4 e5\n\n[diagram]\n\n2. Nf3","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 e5\n\n[diagram]\n\n2. Nf3","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"1. e4 e5 2. Nf3 (2. Bc4 (2... Bc5 3. c3) (2... d6) 2... Nf6 3. d3) Nc6","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 e5 2. Nf3 (2. Bc4 (2... Bc5 3. c3) (2... d6) 2... Nf6 3. d3) Nc6","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"1. e4 d5 2. Pd5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 d5 2. Pd5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 d5 2. d5!","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4 d5 2. d5!","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 (1. d4 e5 2. e5) d5 2. d5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4 (1. d4 e5 2. e5) d5 2. d5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":["unterminatedBraceComment"],"flags":[false,false,false,false],"flat":false,"input":"1. e4 d5 2. d5 Zz9 {open","snapshotDiagnostics":[["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment","unparseableMainlineMove(san: \"Zz9\", plyIndex: 3)"]]},
  {"diagnostics":["unterminatedBraceComment"],"flags":[false,false,false,false],"flat":true,"input":"1. e4 d5 2. d5 Zz9 {open","snapshotDiagnostics":[["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment","unparseableMainlineMove(san: \"Zz9\", plyIndex: 3)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"invalid\"]\n1. e4","snapshotDiagnostics":[["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"invalid\"]\n1. e4","snapshotDiagnostics":[["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"],["invalidFEN(\"invalid\")"]]},
  {"diagnostics":["tagsOnlyRecord"],"flags":[true,true,true,true],"flat":false,"input":"[Event \"Only tags\"]","snapshotDiagnostics":[["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"]]},
  {"diagnostics":["tagsOnlyRecord"],"flags":[true,true,true,true],"flat":true,"input":"[Event \"Only tags\"]","snapshotDiagnostics":[["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"],["tagsOnlyRecord"]]},
  {"diagnostics":["unterminatedBraceComment"],"flags":[false,false,false,false],"flat":false,"input":"1. e4 {open","snapshotDiagnostics":[["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"]]},
  {"diagnostics":["unterminatedBraceComment"],"flags":[false,false,false,false],"flat":true,"input":"1. e4 {open","snapshotDiagnostics":[["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"],["unterminatedBraceComment"]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"1. e4 d5 2. exd5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 d5 2. exd5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"1. e4 d5 2. ed5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 d5 2. ed5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"1. e4 d5 2. e4d5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 d5 2. e4d5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"1. e4 a6 2. e5 d5 3. d6","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"1. e4 a6 2. e5 d5 3. d6","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"1. e4 (1. d4 (1. c4 e5) d5) e5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"1. e4 (1. d4 (1. c4 e5) d5) e5","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(Q) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(Q) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(n) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(n) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8=q {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8=q {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8/Q {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8/Q {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8Q {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8Q {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(K) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(K) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(QQ) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(QQ) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(Q e5) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(Q e5) {promoted} Kh7 (23... Kg7) *","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. Kd2 (23. a8(Q) Kh7) b1=Q","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[true,true,true,true],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. Kd2 (23. a8(Q) Kh7) b1=Q","snapshotDiagnostics":[[],[],[],[],[],[]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":false,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(Q) Kh7 (23... Kg7) 24. Qh1 (24. Qa7)","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]},
  {"diagnostics":[],"flags":[false,false,false,false],"flat":true,"input":"[FEN \"7k/P7/8/8/8/8/1p6/4K3 w - - 0 23\"]\n23. a8(Q) Kh7 (23... Kg7) 24. Qh1 (24. Qa7)","snapshotDiagnostics":[[],[],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"],["unparseableMainlineMove(san: \"a8\", plyIndex: 0)"]]}
]
"""#
}
