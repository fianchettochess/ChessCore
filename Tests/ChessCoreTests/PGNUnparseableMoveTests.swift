import Testing
@testable import ChessCore

/// An unreadable move must not silently produce a different game. Both load
/// paths report it, an abandoned variation cannot leak moves onto the board, and
/// markup that is not a move must not cost a real game its moves.
@Suite("Unparseable PGN moves")
struct PGNUnparseableMoveTests {

    private func parsed(_ text: String) throws -> PGNGame {
        try #require(PGNParser.parse(text).first)
    }

    @Test("Both load paths report the same bad main-line token", arguments: [true, false])
    func bothPathsReportTheBadToken(flat: Bool) throws {
        // Skipping `Zz9` would play Black's d5 in place of the lost move.
        var game = try parsed("1. e4 Zz9 2. d3 d5 *")
        if flat { game.moveTokens = [] }
        let expected = PGNDiagnostic.unparseableMainlineMove(san: "Zz9", plyIndex: 1)

        #expect(PGNParser.parseMainLineSnapshot(from: game).diagnostics.contains(expected))
        #expect(throws: expected) {
            try PGNParser.loadGame(from: game, maximumTreeNodes: PGNParser.maximumMoveTreeNodes)
        }
        // Stored games open through the lenient overload and must keep opening.
        #expect(PGNParser.loadGame(from: game) != nil)
    }

    @Test("A bad variation token drops the rest of that variation only")
    func badVariationTokenLeavesTheMainLine() throws {
        // After `Zz9`, the skipped replay would read Black's Nf6 onto the
        // variation in place of the lost White move.
        let text = "1. e4 e5 (1... c5 Zz9 Nf6 (1... c6 d5) d6) 2. Nf3 (2. d4 d5) Nc6 *"
        let game = try #require(PGNParser.loadGame(from: try parsed(text)))
        let line = game.mainLine
        #expect(line.map(\.notation) == ["e4", "e5", "Nf3", "Nc6"])
        #expect(line[0].children.map(\.notation) == ["e5", "c5"])
        #expect(line[0].children[1].children.isEmpty)
        #expect(line[1].children.map(\.notation) == ["Nf3", "d4"])
    }

    @Test("Markup between moves is not an unreadable move", arguments: [
        "1. e4 ! e5 2. Nf3 *",
        "1. e4 {note} 1. ... e5 2. Nf3 *",
    ])
    func markupKeepsTheGame(text: String) throws {
        let game = try parsed(text)
        #expect(PGNParser.parseMainLineSnapshot(from: game).moves.map(\.notation) == ["e4", "e5", "Nf3"])
        #expect(try PGNParser.loadGame(from: game, maximumTreeNodes: 100).mainLine.map(\.notation) == ["e4", "e5", "Nf3"])
    }

    @Test("An en passant suffix does not end the game")
    func enPassantSuffixKeepsTheGame() throws {
        let game = try parsed("1. e4 d5 2. e5 f5 3. exf6 e.p. Nxf6 *")
        #expect(PGNParser.parseMainLineSnapshot(from: game).moves.count == 6)
        #expect(try PGNParser.loadGame(from: game, maximumTreeNodes: 100).mainLine.count == 6)
    }

    @Test("A null move is not markup")
    func nullMoveIsReported() throws {
        let game = try parsed("1. e4 -- 2. d4 Nf6 *")
        #expect(PGNParser.parseMainLineSnapshot(from: game).moves.isEmpty)
        #expect(throws: PGNDiagnostic.unparseableMainlineMove(san: "--", plyIndex: 1)) {
            try PGNParser.loadGame(from: game, maximumTreeNodes: 100)
        }
    }
}
