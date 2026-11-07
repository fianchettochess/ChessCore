import Testing
@testable import ChessCore

/// Structural validation is a separate admission API; the reader is unchanged.
///
/// Gates b32.153 under the owner's 2026-11-07 rule. Two ways this breaks by
/// accident: wiring the validator into `Position(fen:)`, PGN `[FEN]` loading or
/// snapshot restore would make stored games and setups with a kingless or
/// multi-king board stop opening (the user loses them); weakening a rule would
/// let a new board with no king or two kings into setup or import, where the
/// move generator reports no moves and an engine may abort.
struct PositionStructuralIssueTests {

    private static func square(_ name: String) -> Square { Square(algebraic: name)! }

    /// Golden: older stored FENs that fail admission still read to the same
    /// board, directly and as a PGN setup tag.
    @Test("stored boards that fail admission still restore unchanged",
          arguments: [
              "8/8/8/8/8/8/8/8 w - - 0 1",
              "4k3/8/8/8/8/8/8/K3K3 w - - 0 1",
              "P3k3/8/8/8/8/8/8/4K3 b - - 0 1",
          ])
    func storedBoardsStillRestore(fen: String) throws {
        let position = try #require(Position(fen: fen))
        #expect(position.fen == fen)
        let game = try #require(PGNParser.loadGame(from: "[SetUp \"1\"]\n[FEN \"\(fen)\"]\n\n*\n"))
        #expect(game.startPosition.fen == fen)
    }

    @Test("structural issues are reported in a fixed order",
          arguments: [
              ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", [Position.StructuralIssue]()),
              ("8/8/8/8/8/8/8/8 w - - 0 1", [.missingKing(.white), .missingKing(.black)]),
              ("4k3/8/8/8/8/8/8/K3K3 w - - 0 1", [.extraKing(.white)]),
              ("4k2k/8/8/8/8/8/8/4K3 w - - 0 1", [.extraKing(.black)]),
              ("4k2P/8/8/8/8/8/8/p3K3 b - - 0 1", [.pawnOnBackRank(square("a1")), .pawnOnBackRank(square("h8"))]),
              ("4k3/8/8/8/8/8/8/4R1K1 w - - 0 1", [.sideNotToMoveInCheck(.black)]),
              // Checkmate is a legal position, not a defect.
              ("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", []),
          ])
    func structuralIssues(fen: String, expected: [Position.StructuralIssue]) throws {
        #expect(try #require(Position(fen: fen)).structuralIssues == expected)
    }

    @Test("an en-passant target with no double-pushed pawn behind it is an issue")
    func editedEnPassantTarget() {
        var position = Position.initial()
        position.enPassantTarget = Self.square("e6")
        #expect(position.structuralIssues == [.invalidEnPassantTarget(Self.square("e6"))])
    }

    @Test("strict admission rejects what the reader accepts",
          arguments: [
              ("8/8/8/8/8/8/8/8 w - - 0 1", Position.FENAdmissionIssue.structure(.missingKing(.white))),
              ("4k3/8/8/8/8/8/8/K3K3 w - - 0 1", .structure(.extraKing(.white))),
              // The reader drops the occupied d6 target; admission names it.
              ("rnbqkbnr/ppp1pppp/3N4/3pP3/8/8/PPPP1PPP/R1BQKBNR w KQkq d6 0 3",
               .structure(.invalidEnPassantTarget(square("d6")))),
          ])
    func strictAdmission(fen: String, expected: Position.FENAdmissionIssue) throws {
        #expect(Position(fen: fen) != nil)
        #expect(Position.strictFENIssue(fen) == expected)
        #expect(Position(strictFEN: fen) == nil)
    }

    @Test("a legal position with a real en-passant target is admitted")
    func admittedEnPassant() throws {
        let fen = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3"
        #expect(Position.strictFENIssue(fen) == nil)
        #expect(try #require(Position(strictFEN: fen)).enPassantTarget == Self.square("d6"))
    }
}
