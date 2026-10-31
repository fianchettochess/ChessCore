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

    @Test("Huge counters stay as written and survive a move")
    func hugeCounters() throws {
        // Callers refuse a FEN by its counters, and peers replay the same text,
        // so the parser must not rewrite them.
        let halfmove = "4k3/8/8/8/8/8/8/4K2R w - - \(Int.max) 40"
        var position = try #require(Position(fen: halfmove))
        #expect(position.fen == halfmove)
        try playFirstLegalMove(&position)
        #expect(position.activeColor == .black)
        #expect(position.halfmoveClock == Int.max)

        var fullmove = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R b - - 0 \(Int.max)"))
        try playFirstLegalMove(&fullmove)
        #expect(fullmove.activeColor == .white)
        #expect(fullmove.fullmoveNumber == Int.max)
    }

    @Test("A large counter below the limit still counts exactly")
    func largeCountersStayExact() throws {
        var position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R b - - 2000000 3000000"))
        try playFirstLegalMove(&position)
        #expect(position.halfmoveClock == 2_000_001)
        #expect(position.fullmoveNumber == 3_000_001)
    }

    @Test("PGN export with a huge start fullmove does not trap", arguments: ["w", "b"])
    func exportHugeFullmove(side: String) throws {
        let game = Game()
        #expect(game.loadFEN("4k3/8/8/8/8/8/8/4K2R \(side) - - 0 \(Int.max)"))
        game.apply(try #require(MoveGenerator.legalMoves(for: game.position).first))
        #expect(PGNExporter.export(game: game).contains("... ") == (side == "b"))
    }
}
