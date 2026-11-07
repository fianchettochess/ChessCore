import Foundation

// MARK: - Strict FEN admission
//
// LENIENT READER, STRICT ADMISSION. `Position(fen:)` reads stored positions,
// and it must keep reading every FEN it has ever accepted: a backup, a synced
// row or a saved PGN `[FEN]` tag written years ago has to restore to the same
// board. So the reader stays permissive, and this file states the stricter
// rule separately, for the routes where a NEW position enters from outside
// the library: board setup, a pasted FEN, and a new PGN import (paste, file or
// provider). Those routes call `strictFENIssue(_:)`, `init?(strictFEN:)` or
// `structuralIssues`. Nothing that reads stored data does: backup restore,
// sync, snapshot restore and re-reading or re-importing a stored row all use
// the lenient reader.
//
// What ChessCore writes already passes: `fen` and `positionKey` always emit
// eight ranks separated by single slashes.

extension Position {

    /// Why a FEN must not be admitted as a new position.
    ///
    /// New cases may be added in a minor release.
    public enum FENAdmissionIssue: Equatable, Hashable, Sendable {
        /// `Position(fen:)` cannot read the text at all.
        case unreadable
        /// The placement field has an empty rank segment: `//`, or a leading
        /// or trailing `/`. The reader skips empty segments so previously
        /// stored positions still restore; a new FEN must have exactly eight
        /// ranks separated by single slashes.
        case emptyRankSegment
        /// The text reads, but the board it describes fails
        /// ``Position/structuralIssues``. Carries the first issue found.
        case structure(StructuralIssue)
    }

    /// A placement or metadata defect no legal game can produce.
    ///
    /// `Position(fen:)` reads all of these, so stored positions keep
    /// restoring; admission routes reject them. Case names follow
    /// FianchettoKit's `PositionDefect` where the two overlap. New cases may
    /// be added in a minor release.
    public enum StructuralIssue: Equatable, Hashable, Sendable {
        /// This colour has no king.
        case missingKing(PieceColor)
        /// This colour has more than one king.
        case duplicateKing(PieceColor)
        /// A pawn stands on the first or eighth rank, where no pawn can be.
        case pawnOnBackRank(Square)
        /// The side that just moved left its own king in check.
        case sideNotToMoveInCheck(PieceColor)
        /// A castling right the placement cannot support: the king is not on
        /// its start square, or the named rook is not on its start square.
        /// Carries the rook's start square, which names the right (h1 is
        /// White kingside, a1 White queenside, h8 and a8 Black's). The reader
        /// keeps such a right; ``Position/consistentFEN`` drops it.
        case unsupportedCastlingRight(Square)
        /// An en-passant target that is not on the side-to-move's sixth rank,
        /// is occupied, or has no enemy pawn on the square past it (where the
        /// double-pushed pawn now stands). The reader drops such a target from
        /// a FEN; this reports that it did.
        case invalidEnPassantTarget(Square)
        /// An otherwise valid en-passant target whose pawn's start square is
        /// occupied, so the pawn cannot just have double-pushed from there.
        /// Carries the start square (e7 for a target on e6).
        case occupiedEnPassantOrigin(Square)
    }

    /// Every structural defect in this position, in a fixed order: king
    /// counts (White, then Black), back-rank pawns (a1 to h8), castling
    /// rights (h1, a1, h8, a8), the en-passant target and its pawn's start
    /// square, then a check against the side not to move. Empty
    /// when the position could stand on a board in a legal game, as far as
    /// these rules can tell; checkmate and stalemate are not defects.
    ///
    /// Returns all issues rather than a verdict, so an admission route can
    /// choose which to enforce. The check test runs only when each side has
    /// exactly one king, because it needs to know which square is the king's.
    public var structuralIssues: [StructuralIssue] {
        var issues: [StructuralIssue] = []
        var kingSquares: [PieceColor: [Square]] = [:]
        for index in 0..<64 {
            guard let piece = board[index] else { continue }
            let square = Square.fromIndex(index)
            if piece.type == .king { kingSquares[piece.color, default: []].append(square) }
        }
        for color in [PieceColor.white, .black] {
            switch kingSquares[color]?.count ?? 0 {
            case 0: issues.append(.missingKing(color))
            case 1: break
            default: issues.append(.duplicateKing(color))
            }
        }
        for index in 0..<64 where board[index]?.type == .pawn {
            let square = Square.fromIndex(index)
            if square.rank == 0 || square.rank == 7 { issues.append(.pawnOnBackRank(square)) }
        }
        let supported = sanitizedCastlingRights
        for (claimed, kept, rook) in [
            (castlingRights.whiteKingside, supported.whiteKingside, Square(file: 7, rank: 0)),
            (castlingRights.whiteQueenside, supported.whiteQueenside, Square(file: 0, rank: 0)),
            (castlingRights.blackKingside, supported.blackKingside, Square(file: 7, rank: 7)),
            (castlingRights.blackQueenside, supported.blackQueenside, Square(file: 0, rank: 7)),
        ] where claimed && !kept {
            issues.append(.unsupportedCastlingRight(rook))
        }
        if let target = enPassantTarget {
            if !Position.isValidEnPassantTarget(target, in: self) {
                issues.append(.invalidEnPassantTarget(target))
            } else {
                let origin = Square(file: target.file, rank: activeColor == .white ? 6 : 1)
                if self[origin] != nil { issues.append(.occupiedEnPassantOrigin(origin)) }
            }
        }
        let waiting = activeColor.opposite
        if kingSquares[.white]?.count == 1, kingSquares[.black]?.count == 1,
           let king = kingSquares[waiting]?.first,
           MoveGenerator.isSquareAttacked(king, by: activeColor, in: self) {
            issues.append(.sideNotToMoveInCheck(waiting))
        }
        return issues
    }

    /// The rule the reader applies to a FEN's en-passant field: the target
    /// is on the side-to-move's sixth rank, empty, with the opponent's pawn
    /// directly in front of it.
    private static func isValidEnPassantTarget(_ target: Square, in position: Position) -> Bool {
        let white = position.activeColor == .white
        guard target.rank == (white ? 5 : 2), position[target] == nil else { return false }
        let pawn = Square(file: target.file, rank: white ? target.rank - 1 : target.rank + 1)
        return position[pawn] == Piece(type: .pawn, color: white ? .black : .white)
    }

    /// The reason `fen` must not be admitted as a new position, or `nil` when
    /// it may be.
    ///
    /// Whitespace around and between fields is accepted, as the reader
    /// accepts it: a pasted FEN with a trailing space is still a good FEN.
    public static func strictFENIssue(_ fen: String) -> FENAdmissionIssue? {
        let fields = fen.split(whereSeparator: \.isWhitespace)
        guard let position = Position(fen: fen), let placement = fields.first else { return .unreadable }
        if placement.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: \.isEmpty) {
            return .emptyRankSegment
        }
        // The reader silently drops an en-passant field it cannot honour, so
        // the parsed position no longer shows it. Admission reports it.
        if position.enPassantTarget == nil, fields.count > 3, fields[3] != "-",
           let written = Square(algebraic: String(fields[3])) {
            return .structure(.invalidEnPassantTarget(written))
        }
        if let issue = position.structuralIssues.first { return .structure(issue) }
        return nil
    }

    /// Reads `fen` only when it passes ``strictFENIssue(_:)``. Use it where a
    /// new position is admitted; use ``init(fen:)`` to restore stored data.
    public init?(strictFEN fen: String) {
        guard Position.strictFENIssue(fen) == nil, let position = Position(fen: fen) else { return nil }
        self = position
    }
}
