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
              // Castling rights with no king or rook behind them.
              "4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1",
              // An en-passant target whose pawn's start square is occupied.
              "rnbqkb1r/ppppnppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 3",
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
              ("4k3/8/8/8/8/8/8/K3K3 w - - 0 1", [.duplicateKing(.white)]),
              ("4k2k/8/8/8/8/8/8/4K3 w - - 0 1", [.duplicateKing(.black)]),
              ("4k2P/8/8/8/8/8/8/p3K3 b - - 0 1", [.pawnOnBackRank(square("a1")), .pawnOnBackRank(square("h8"))]),
              ("4k3/8/8/8/8/8/8/4R1K1 w - - 0 1", [.sideNotToMoveInCheck(.black)]),
              // The check test needs exactly one king each. Here the waiting
              // side's first king (a8) is attacked, and with no king of its
              // own (e8 attacked, no White king) a check would be reported
              // against a board whose king count is already wrong.
              ("k6k/8/8/8/8/8/8/R3K3 w - - 0 1", [.duplicateKing(.black)]),
              ("4k3/8/8/8/8/8/8/4R3 w - - 0 1", [.missingKing(.white)]),
              // Checkmate is a legal position, not a defect.
              ("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", []),
          ])
    func structuralIssues(fen: String, expected: [Position.StructuralIssue]) throws {
        #expect(try #require(Position(fen: fen)).structuralIssues == expected)
    }

    @Test("a castling right needs its king and rook on their start squares",
          arguments: [
              ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", [Position.StructuralIssue]()),
              ("4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1",
               [.unsupportedCastlingRight(square("h1")), .unsupportedCastlingRight(square("a1")),
                .unsupportedCastlingRight(square("h8")), .unsupportedCastlingRight(square("a8"))]),
              // King off its start square.
              ("r3k2r/8/8/8/8/8/8/R4K1R w KQ - 0 1",
               [.unsupportedCastlingRight(square("h1")), .unsupportedCastlingRight(square("a1"))]),
              // The named rook is absent.
              ("r3k3/8/8/8/8/8/8/R3K2R b k - 0 1", [.unsupportedCastlingRight(square("h8"))]),
              // The piece on the rook's square is the wrong colour.
              ("4k3/8/8/8/8/8/8/4K2r w K - 0 1", [.unsupportedCastlingRight(square("h1"))]),
          ])
    func castlingRights(fen: String, expected: [Position.StructuralIssue]) throws {
        #expect(try #require(Position(fen: fen)).structuralIssues == expected)
    }

    @Test("an en-passant target needs its pawn's start square empty",
          arguments: [
              ("rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3", [Position.StructuralIssue]()),
              ("rnbqkb1r/ppppnppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 3",
               [.occupiedEnPassantOrigin(square("e7"))]),
              ("rnbqkbnr/pppppppp/8/8/3P4/8/PPPBPPPP/RN1QKBNR b KQkq d3 0 1",
               [.occupiedEnPassantOrigin(square("d2"))]),
          ])
    func enPassantOrigin(fen: String, expected: [Position.StructuralIssue]) throws {
        let position = try #require(Position(fen: fen))
        #expect(position.enPassantTarget != nil)
        #expect(position.structuralIssues == expected)
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
              ("4k3/8/8/8/8/8/8/K3K3 w - - 0 1", .structure(.duplicateKing(.white))),
              // The reader drops the occupied d6 target; admission names it.
              // The bishop on d6 attacks nothing else, so the target is the
              // board's only defect.
              ("rnbqkbnr/ppp1pppp/3B4/3pP3/8/8/PPPP1PPP/RN1QKBNR w KQkq d6 0 3",
               .structure(.invalidEnPassantTarget(square("d6")))),
              ("4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1", .structure(.unsupportedCastlingRight(square("h1")))),
              ("rnbqkb1r/ppppnppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 3",
               .structure(.occupiedEnPassantOrigin(square("e7")))),
          ])
    func strictAdmission(fen: String, expected: Position.FENAdmissionIssue) throws {
        let position = try #require(Position(fen: fen))
        if case .structure(.invalidEnPassantTarget) = expected {
            #expect(position.structuralIssues.isEmpty)
        }
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
