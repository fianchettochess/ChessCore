import Testing
@testable import ChessCore

/// Placement edits must update the king used by check detection and legal moves.
/// A stale cache otherwise rejects a safe correction or permits moves in check.
struct PositionPlacementEditingTests {
    @Test(arguments: [PieceColor.white, .black], [false, true])
    func kingDragUpdatesCheckDetection(color: PieceColor, destinationFirst: Bool) throws {
        let fen = color == .white
            ? "4r2k/8/8/8/8/8/8/4K3 w - - 0 1"
            : "4k3/8/8/8/8/8/8/4R2K b - - 0 1"
        var position = try #require(Position(fen: fen))
        let source = Square(file: 4, rank: color == .white ? 0 : 7)
        let target = Square(file: 3, rank: color == .white ? 1 : 6)
        let king = try #require(position[source])
        #expect(MoveGenerator.isInCheck(position))
        if destinationFirst {
            position[target] = king; position[source] = nil
        } else {
            position[source] = nil; position[target] = king
        }
        #expect(MoveGenerator.findKing(in: position, color: color) == target)
        #expect(!MoveGenerator.isInCheck(position))
        #expect(!MoveGenerator.legalMoves(for: position).isEmpty)
        position[source] = king; position[target] = nil
        #expect(MoveGenerator.isInCheck(position))
    }

    @Test func erasingAnExtraKingRestoresTheRemainingKingsLocation() throws {
        var position = try #require(Position(fen: "4r2k/8/8/8/8/8/8/4K3 w - - 0 1"))
        let extra = Square(file: 3, rank: 1)
        position[extra] = Piece(type: .king, color: .white)
        position[extra] = nil
        #expect(MoveGenerator.isInCheck(position))
        #expect(MoveGenerator.findKing(in: position, color: .white) == Square(file: 4, rank: 0))
    }
}
