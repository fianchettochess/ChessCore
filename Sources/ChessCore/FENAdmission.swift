import Foundation

// MARK: - Strict FEN admission
//
// LENIENT READER, STRICT ADMISSION. `Position(fen:)` reads stored positions,
// and it must keep reading every FEN it has ever accepted: a backup, a synced
// row or a saved PGN `[FEN]` tag written years ago has to restore to the same
// board. So the reader stays permissive, and this file states the stricter
// rule separately, for the routes where a NEW position enters (board setup,
// pasted FENs, PGN import). Those routes call `strictFENIssue(_:)` or
// `init?(strictFEN:)`; nothing that restores stored data does.
//
// What ChessCore writes already passes: `fen` and `positionKey` always emit
// eight ranks separated by single slashes.

extension Position {

    /// Why a FEN must not be admitted as a new position.
    public enum FENAdmissionIssue: Equatable, Hashable, Sendable {
        /// `Position(fen:)` cannot read the text at all.
        case unreadable
        /// The placement field has an empty rank segment: `//`, or a leading
        /// or trailing `/`. The reader skips empty segments so previously
        /// stored positions still restore; a new FEN must have exactly eight
        /// ranks separated by single slashes.
        case emptyRankSegment
    }

    /// The reason `fen` must not be admitted as a new position, or `nil` when
    /// it may be.
    ///
    /// Whitespace around and between fields is accepted, as the reader
    /// accepts it: a pasted FEN with a trailing space is still a good FEN.
    public static func strictFENIssue(_ fen: String) -> FENAdmissionIssue? {
        guard Position(fen: fen) != nil,
              let placement = fen.split(whereSeparator: \.isWhitespace).first
        else { return .unreadable }
        if placement.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: \.isEmpty) {
            return .emptyRankSegment
        }
        return nil
    }

    /// Reads `fen` only when it passes ``strictFENIssue(_:)``. Use it where a
    /// new position is admitted; use ``init(fen:)`` to restore stored data.
    public init?(strictFEN fen: String) {
        guard Position.strictFENIssue(fen) == nil, let position = Position(fen: fen) else { return nil }
        self = position
    }
}
