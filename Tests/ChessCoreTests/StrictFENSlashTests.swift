import Testing
@testable import ChessCore

/// Slash structure: lenient when restoring, strict when admitting.
///
/// Gates the owner's 2026-11-07 rule for b32.154. Tightening `Position(fen:)`
/// itself would make previously stored positions with a stray slash fail to
/// restore (the user loses the game or setup); loosening `strictFENIssue`
/// would let a malformed pasted FEN into the library as a new position.
struct StrictFENSlashTests {

    /// Golden from an older stored value: a trailing slash and a doubled
    /// slash, both of which the reader has always skipped.
    @Test("a stored FEN with stray slashes still restores to the same board")
    func storedStraySlashesStillRestore() throws {
        let stored = "r1bqkbnr/pppp1ppp/2n5//4p3/4P3/5N2/PPPP1PPP/RNBQKB1R/ w KQkq - 2 3"
        let position = try #require(Position(fen: stored))
        #expect(position.fen == "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3")
    }

    @Test("strict admission rejects empty rank segments",
          arguments: [
              "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR/ w KQkq - 0 1",
              "/rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
              "rnbqkbnr/pppppppp/8//8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
              "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR// b KQkq -",
          ])
    func emptySegmentsRejected(fen: String) {
        #expect(Position(fen: fen) != nil)
        #expect(Position.strictFENIssue(fen) == .emptyRankSegment)
        #expect(Position(strictFEN: fen) == nil)
    }

    @Test("strict admission accepts surrounding and repeated whitespace",
          arguments: [
              "  rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1 ",
              "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR  b\tKQkq e3 0 1",
              "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3\n",
          ])
    func whitespaceAccepted(fen: String) throws {
        #expect(Position.strictFENIssue(fen) == nil)
        let position = try #require(Position(strictFEN: fen))
        #expect(position == Position(fen: fen))
    }

    @Test("text the reader cannot read is unreadable, not a slash issue",
          arguments: ["", "   ", "not a fen", "8/8/8/8/8/8/8 w - - 0 1"])
    func unreadable(fen: String) {
        #expect(Position.strictFENIssue(fen) == .unreadable)
    }

    /// The writer half: every FEN ChessCore writes must pass its own strict
    /// admission, or exporting and re-importing a position would refuse it.
    @Test("what ChessCore writes passes strict admission",
          arguments: [
              "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
              "r1bqkbnr/pppp1ppp/2n5//4p3/4P3/5N2/PPPP1PPP/RNBQKB1R/ w KQkq - 2 3",
              "8/8/8/8/8/8/8/k6K b - - 50 80",
          ])
    func writtenFENsAreAdmitted(source: String) throws {
        let position = try #require(Position(fen: source))
        #expect(Position.strictFENIssue(position.fen) == nil)
        #expect(Position.strictFENIssue(position.positionKey) == nil)
    }
}
