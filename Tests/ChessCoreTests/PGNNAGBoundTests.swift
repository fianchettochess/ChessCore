import Testing
@testable import ChessCore

/// NAG numbers outside the standard 0...255 range, and outside `Int`.
///
/// Decision (b32.152, under the 2026-11-07 lenient-reader rule): an
/// out-of-range NAG never costs the game or its moves. The tokenizer emits
/// exactly the tokens it always has, because tokens feed stored-row identity:
/// `$300` stays `.nag(300)` and is reported as uncarried, and a standalone
/// digit run too long for `Int` stays the word it was and is reported as a
/// dropped token. What changed is the attached form: `e4$99999999999999999999`
/// used to make the move unreadable, which dropped it and every move after it
/// in that line. Its NAG is now dropped and the move kept.
struct PGNNAGBoundTests {

    private static func spelled(_ tokens: [PGNToken]) -> [String] {
        tokens.map {
            switch $0 {
            case .move(let san): "move \(san)"
            case .nag(let number): "nag \(number)"
            case .comment(let text): "comment \(text)"
            case .variationStart: "("
            case .variationEnd: ")"
            }
        }
    }

    /// Golden from a realistic older export: standard NAGs, a nonstandard
    /// `$300` and an overflowing standalone NAG. Gates the tokenizer: clamping,
    /// dropping or re-reading any of these would change tokens, so re-importing
    /// a stored game would create a duplicate row instead of matching its own.
    @Test("out-of-range standalone NAGs keep the tokens, text and moves they always had")
    func standaloneGolden() throws {
        let pgn = """
        [Event "Club Championship"]
        [Site "?"]
        [Date "2009.03.14"]
        [Round "4"]
        [White "Hall, R."]
        [Black "Okafor, T."]
        [Result "1-0"]

        1. e4 $1 c5 2. Nf3 d6 $14 3. d4 cxd4 4. Nxd4 $18 Nf6 5. Nc3 $146 a6 $300
        6. Be3 $99999999999999999999 e5 1-0
        """
        let parsed = try #require(PGNParser.parse(pgn).first)
        #expect(Self.spelled(parsed.moveTokens) == [
            "move e4", "nag 1", "move c5", "move Nf3", "move d6", "nag 14",
            "move d4", "move cxd4", "move Nxd4", "nag 18", "move Nf6",
            "move Nc3", "nag 146", "move a6", "nag 300",
            "move Be3", "move $99999999999999999999", "move e5",
        ])
        #expect(PGNExporter.tokenText(from: parsed)
            == "e4 $1 c5 Nf3 d6 $14 d4 cxd4 Nxd4 $18 Nf6 Nc3 $146 a6 $300 Be3 $99999999999999999999 e5")
        let report = try #require(PGNParser.loadGameWithReport(from: parsed))
        #expect(PGNExporter.moveText(for: report.game.rootChildren)
            == "1. e4! c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e5")
        #expect(report.uncarriedText.contains("$300"))
        #expect(report.droppedMoveTokens == ["$99999999999999999999"])
    }

    /// Gates `readableMoveWord`: without the overflow arm the attached NAG
    /// leaves the word unreadable, and the user's game silently loses that
    /// move and the rest of its line.
    @Test("an attached NAG too large for Int is dropped and the move kept",
          arguments: [
              ("1. e4$99999999999999999999 e5 2. Nf3", "1. e4 e5 2. Nf3"),
              ("1. e4 e5$123456789012345678901234567890 2. Nf3", "1. e4 e5 2. Nf3"),
              ("1. e4 ( 1. d4$99999999999999999999 d5 ) e5 2. Nf3", "1. e4 ( 1. d4 d5 ) e5 2. Nf3"),
          ])
    func attachedOverflow(text: String, expected: String) throws {
        let parsed = try #require(PGNParser.parse(text).first)
        let report = try #require(PGNParser.loadGameWithReport(from: parsed))
        #expect(PGNExporter.moveText(for: report.game.rootChildren) == expected)
        #expect(report.droppedMoveTokens.isEmpty)
        #expect(!report.canReplaceStoredText)
        #expect(PGNParser.parseMainLineSnapshot(from: parsed).moves.count == 3)
    }
}
