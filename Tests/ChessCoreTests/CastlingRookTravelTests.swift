import Testing
@testable import ChessCore

/// `Move.castlingRookTravel`, and the two ways it can be asked wrongly.
///
/// The rook squares used to be written inline in `MoveGenerator.applyMove` and
/// again in a consumer that had to draw the same castle, which is two places to
/// disagree about a rule neither of them chose. The fact now has one home.
@Suite("Castling rook travel")
struct CastlingRookTravelTests {

    private func castle(to file: Int, rank: Int) -> Move {
        Move(
            from: Square(file: 4, rank: rank),
            to: Square(file: file, rank: rank),
            piece: .king,
            isCastling: true
        )
    }

    @Test("Kingside sends the rook from the h-file to the f-file")
    func kingside() throws {
        let travel = try #require(castle(to: 6, rank: 0).castlingRookTravel)
        #expect(travel.from == Square(file: 7, rank: 0))
        #expect(travel.to == Square(file: 5, rank: 0))
    }

    @Test("Queenside sends the rook from the a-file to the d-file")
    func queenside() throws {
        let travel = try #require(castle(to: 2, rank: 7).castlingRookTravel)
        #expect(travel.from == Square(file: 0, rank: 7))
        #expect(travel.to == Square(file: 3, rank: 7))
    }

    @Test("The rook stays on the king's rank, for either colour")
    func staysOnRank() throws {
        for rank in [0, 7] {
            for file in [6, 2] {
                let travel = try #require(castle(to: file, rank: rank).castlingRookTravel)
                #expect(travel.from.rank == rank)
                #expect(travel.to.rank == rank)
            }
        }
    }

    // MARK: - The two refusals

    /// An ordinary king move is not a castle, however king-like it looks.
    @Test("A move not flagged as castling describes no rook travel")
    func notCastling() {
        let step = Move(
            from: Square(file: 4, rank: 0),
            to: Square(file: 5, rank: 0),
            piece: .king
        )
        #expect(step.castlingRookTravel == nil)
    }

    /// A move flagged as castling whose destination is neither file is
    /// malformed. Guessing a rook for it would move a piece that should not
    /// move, which is worse than declining to answer.
    @Test("A castling flag on an impossible destination is refused, not guessed")
    func malformedDestination() {
        for file in [0, 1, 3, 4, 5, 7] {
            #expect(castle(to: file, rank: 0).castlingRookTravel == nil, "file \(file)")
        }
    }
}
