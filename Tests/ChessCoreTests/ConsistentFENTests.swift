import Testing
import Foundation
import ChessCore

/// `Position.consistentFEN` — the FEN that survives a round trip because its
/// castling rights and en-passant square agree with the board.
///
/// Renamed from `StockfishSafeFENTests`, which lived in the Apple app's test
/// target. Nothing here is about Stockfish, or about Fianchetto: the suite
/// imports only ChessCore and asserts only on `Position`. It was named for the
/// caller that motivated it — an engine that rejects an inconsistent FEN — and
/// a vendor name on a ChessCore suite is what PACKAGE_BOUNDARY.md's question 4
/// exists to catch. `consistentFEN` had no test in this package at all.
/// (post-severance audit 2026-08-22)
@Suite
struct ConsistentFENTests {

    /// Starting position FEN should round-trip unchanged — every castling
    /// right is legitimate (king on e1/e8, rooks on a1/h1/a8/h8).
    @Test func initialPositionPassesThroughIntact() throws {
        let pos = Position.initial()
        let safe = try #require(Position(fen: pos.consistentFEN))
        #expect(safe.castlingRights == CastlingRights(
            whiteKingside: true, whiteQueenside: true,
            blackKingside: true, blackQueenside: true
        ))
    }

    /// Position with kings off their home squares but castling-rights field
    /// still set (this was the crash trigger) — sanitiser must zero out
    /// every right.
    @Test func castlingStrippedWhenKingsAreOffHome() throws {
        var pos = Position()
        pos[Square(file: 3, rank: 1)] = Piece(type: .king, color: .white)
        pos[Square(file: 4, rank: 4)] = Piece(type: .king, color: .black)
        pos.whiteKingSquare = Square(file: 3, rank: 1)
        pos.blackKingSquare = Square(file: 4, rank: 4)
        // Position() defaults castlingRights to all-true; that's the bug
        // the sanitiser exists to guard against.
        #expect(pos.castlingRights == CastlingRights(
            whiteKingside: true, whiteQueenside: true,
            blackKingside: true, blackQueenside: true
        ))
        let safe = try #require(Position(fen: pos.consistentFEN))
        #expect(safe.castlingRights == .none)
    }

    /// Kings on their home squares but the rooks aren't — Stockfish would
    /// loop off the board hunting for them. Sanitiser drops the rights for
    /// the missing rooks only, keeping anything still consistent.
    @Test func castlingStrippedPerMissingRook() throws {
        var pos = Position()
        // White: king on home, only kingside rook present.
        pos[Square(file: 4, rank: 0)] = Piece(type: .king, color: .white)
        pos[Square(file: 7, rank: 0)] = Piece(type: .rook, color: .white)
        // Black: king on home, only queenside rook present.
        pos[Square(file: 4, rank: 7)] = Piece(type: .king, color: .black)
        pos[Square(file: 0, rank: 7)] = Piece(type: .rook, color: .black)
        pos.whiteKingSquare = Square(file: 4, rank: 0)
        pos.blackKingSquare = Square(file: 4, rank: 7)

        let safe = try #require(Position(fen: pos.consistentFEN))
        #expect(safe.castlingRights.whiteKingside)
        #expect(!safe.castlingRights.whiteQueenside)
        #expect(!safe.castlingRights.blackKingside)
        #expect(safe.castlingRights.blackQueenside)
    }

    /// En-passant target square should be dropped if the pawn that would
    /// have just moved isn't actually there.
    @Test func enPassantStrippedWhenNoPawnMatches() throws {
        var pos = Position()
        pos[Square(file: 4, rank: 0)] = Piece(type: .king, color: .white)
        pos[Square(file: 4, rank: 7)] = Piece(type: .king, color: .black)
        pos.whiteKingSquare = Square(file: 4, rank: 0)
        pos.blackKingSquare = Square(file: 4, rank: 7)
        // Claim e3 is an en-passant target (would require a white pawn on
        // e4), but the board is empty there.
        pos.enPassantTarget = Square(file: 4, rank: 2)

        let safe = try #require(Position(fen: pos.consistentFEN))
        #expect(safe.enPassantTarget == nil)
    }

    /// Valid en-passant configuration (white pawn just pushed e2→e4) should
    /// survive sanitisation.
    @Test func enPassantPreservedWhenPawnMatches() throws {
        var pos = Position()
        pos[Square(file: 4, rank: 0)] = Piece(type: .king, color: .white)
        pos[Square(file: 4, rank: 7)] = Piece(type: .king, color: .black)
        pos[Square(file: 4, rank: 3)] = Piece(type: .pawn, color: .white)
        pos.whiteKingSquare = Square(file: 4, rank: 0)
        pos.blackKingSquare = Square(file: 4, rank: 7)
        pos.enPassantTarget = Square(file: 4, rank: 2)
        pos.activeColor = .black

        let safe = try #require(Position(fen: pos.consistentFEN))
        #expect(safe.enPassantTarget == Square(file: 4, rank: 2))
    }
}
