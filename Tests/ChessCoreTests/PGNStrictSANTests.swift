import Testing
@testable import ChessCore

/// A token that is not SAN must stop the replay. Reading it as whichever legal
/// move shares its last two characters makes a sloppy PGN describe a different
/// game, with nothing to tell the user the import went wrong.
@Suite("Strict SAN parsing")
struct PGNStrictSANTests {

    @Test("Malformed tokens never resolve to a legal move", arguments: [
        // Wrong or unknown piece letter read as a pawn push.
        "nf3", "rf3", "Zf3",
        // Garbage around the target square.
        "xyzf3", "xf3", "Nf3x", "e4x", "Nxxf3", "N?f3",
        // Characters that are neither a file nor a rank in the origin.
        "Nzf3", "N f3",
        // A pawn origin needs a file.
        "2e4",
        // Anything other than one promotion letter after the equals sign.
        "e4=Z",
    ])
    func malformedTokenIsRejected(token: String) {
        #expect(PGNParser.parseMove(token, in: .initial()) == nil)
    }

    @Test("A trailing promotion token cannot carry extra characters")
    func promotionWithTrailingGarbageIsRejected() throws {
        let position = try #require(Position(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"))
        #expect(PGNParser.parseMove("a8=Qxyz", in: position) == nil)
        #expect(PGNParser.parseMove("a8=Q+", in: position)?.promotion == .queen)
    }

    @Test("A hyphen needs a whole origin square, and long algebraic keeps parsing")
    func hyphenRequiresOriginSquare() {
        #expect(PGNParser.parseMove("e2-e4", in: .initial())?.uci == "e2e4")
        #expect(PGNParser.parseMove("Ng1-f3", in: .initial())?.uci == "g1f3")
        #expect(PGNParser.parseMove("Ng1xf3", in: .initial())?.uci == "g1f3")
        #expect(PGNParser.parseMove("-e4", in: .initial()) == nil)
        #expect(PGNParser.parseMove("e-e4", in: .initial()) == nil)
        #expect(PGNParser.parseMove("N-f3", in: .initial()) == nil)
    }

    @Test("Check and quality marks are read only where they trail the move")
    func marksOnlyTrail() {
        #expect(PGNParser.parseMove("e4+", in: .initial())?.uci == "e2e4")
        #expect(PGNParser.parseMove("Ng1f3!?", in: .initial())?.uci == "g1f3")
        #expect(PGNParser.parseMove("+e4", in: .initial()) == nil)
        #expect(PGNParser.parseMove("e+4", in: .initial()) == nil)
    }

    @Test("A PGN with a lowercase piece letter reports it instead of playing a pawn")
    func importReportsLowercasePieceLetter() {
        let parsed = PGNParser.mainLineSnapshot(fromMoveText: "1. nf3 d5 *")
        #expect(parsed.moves.isEmpty)
        #expect(parsed.diagnostics.contains(.unparseableMainlineMove(san: "nf3", plyIndex: 0)))
    }
}
