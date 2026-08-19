import Testing
@testable import ChessCore

/// Whether one named side retains material that could deliver mate.
///
/// The unilateral question FIDE 6.9 needs at a flag fall, as distinct from
/// `hasInsufficientMaterial`, which asks whether NEITHER side can mate.
struct MatingMaterialTests {

    private func position(_ fen: String) throws -> Position {
        try #require(Position(fen: fen))
    }

    // MARK: - Cannot mate

    @Test("A bare king can never mate") func bareKing() throws {
        // White: K only. Black: K+Q.
        let p = try position("7k/8/8/8/8/8/7q/K7 w - - 0 1")
        #expect(!p.hasMatingMaterial(for: .white))
        #expect(p.hasMatingMaterial(for: .black))
    }

    @Test("A lone minor cannot mate") func loneMinor() throws {
        let knight = try position("7k/8/8/8/8/8/8/KN6 w - - 0 1")
        #expect(!knight.hasMatingMaterial(for: .white))
        let bishop = try position("7k/8/8/8/8/8/8/KB6 w - - 0 1")
        #expect(!bishop.hasMatingMaterial(for: .white))
    }

    // MARK: - Can mate

    @Test("Two minors can mate") func twoMinors() throws {
        let bishopKnight = try position("7k/8/8/8/8/8/8/KBN5 w - - 0 1")
        #expect(bishopKnight.hasMatingMaterial(for: .white))
        // K+N+N cannot FORCE mate, but a mate position exists and this is a
        // material test — the convention counts it.
        let twoKnights = try position("7k/8/8/8/8/8/8/KNN5 w - - 0 1")
        #expect(twoKnights.hasMatingMaterial(for: .white))
    }

    @Test("A pawn counts, because it promotes") func pawnPromotes() throws {
        let p = try position("7k/8/8/8/8/8/P7/K7 w - - 0 1")
        #expect(p.hasMatingMaterial(for: .white))
    }

    @Test("Rook and queen mate") func majors() throws {
        #expect(try position("7k/8/8/8/8/8/8/KR6 w - - 0 1").hasMatingMaterial(for: .white))
        #expect(try position("7k/8/8/8/8/8/8/KQ6 w - - 0 1").hasMatingMaterial(for: .white))
    }

    // MARK: - It is unilateral, and that is the whole point

    /// THE CASE THAT SHIPS WRONG WITHOUT THIS. White has a bare king and Black
    /// has a queen. `hasInsufficientMaterial` is FALSE — a queen is on the
    /// board, so the position is not dead — yet White still cannot mate. Only
    /// the per-colour question catches it, and that is exactly the flag-fall
    /// case: if Black's clock expires, White must not be awarded the win.
    @Test("A side can be unable to mate in a position that is not dead")
    func unilateralDiffersFromBilateral() throws {
        let p = try position("7k/8/8/8/8/8/7q/K7 w - - 0 1")
        #expect(!p.hasInsufficientMaterial, "a queen on the board is not a dead position")
        #expect(!p.hasMatingMaterial(for: .white), "but White still cannot mate")
    }

    /// NEGATIVE CONTROL for the colour argument: the same position answers
    /// differently for each side, so an implementation ignoring `color` — the
    /// natural mistake when adapting the bilateral version — fails here.
    @Test("The answer depends on which colour is asked") func colourMatters() throws {
        let p = try position("7k/8/8/8/8/8/7q/K7 w - - 0 1")
        #expect(p.hasMatingMaterial(for: .black) != p.hasMatingMaterial(for: .white))
    }
}
