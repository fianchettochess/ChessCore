import Testing
@testable import ChessCore

/// FEN arrives from shared PGNs, links, backups and Continuity payloads. A
/// counter near `Int.max` used to pass the parser and then trap the process on
/// the next move or export, so a stored row could crash every time it opened.
@Suite("FEN move counter bounds")
struct MoveCounterBoundsTests {
    private func playFirstLegalMove(_ position: inout Position) throws {
        let move = try #require(MoveGenerator.legalMoves(for: position).first)
        MoveGenerator.applyMoveUnchecked(&position, move)
    }

    @Test("A huge halfmove clock still loads and survives a move")
    func hugeHalfmoveClock() throws {
        var position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R w - - \(Int.max) 40"))
        #expect(position.fullmoveNumber == 40)
        try playFirstLegalMove(&position)
        #expect(position.activeColor == .black)

        // The cap must stay above anything a real game or tool writes.
        let plausible = "4k3/8/8/8/8/8/8/4K2R w - - 149 5000"
        #expect(Position(fen: plausible)?.fen == plausible)
    }

    @Test("A huge fullmove number still loads and survives Black's move")
    func hugeFullmoveNumber() throws {
        var position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R b - - 0 \(Int.max)"))
        try playFirstLegalMove(&position)
        #expect(position.activeColor == .white)
    }

    @Test("Counters that bypassed the FEN parser cannot trap a move")
    func directlySetCounters() throws {
        var position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R b - - 0 1"))
        position.halfmoveClock = Int.max
        position.fullmoveNumber = Int.max
        try playFirstLegalMove(&position)
        #expect(position.activeColor == .white)
    }

    @Test("PGN export with a huge start fullmove does not trap", arguments: ["w", "b"])
    func exportHugeFullmove(side: String) throws {
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/8/4K2R \(side) - - 0 \(Int.max)"))
        game.apply(try #require(MoveGenerator.legalMoves(for: game.position).first))
        #expect(PGNExporter.export(game: game).contains("... ") == (side == "b"))
    }
}
