import Foundation

/// Bounded, thread-safe cache for `MoveGenerator.legalMoves(for:)` results,
/// keyed on `Position.positionKey` (board + side + castling + en-passant —
/// the fields that determine legality). Legal moves are fully determined by
/// position (no side effects), so cached values never need invalidation; we cap
/// the dictionary size with cheap eviction to keep memory bounded.
///
/// This lifts a per-call cost that fanned out across every chess surface in
/// the app — move-list rendering, opening-book continuation resolution,
/// repertoire-builder lookups, board-arrow computation, annotation, etc.
///
/// Uses `NSLock` (portable: Apple + Linux + Android) rather than the Darwin-only
/// `OSAllocatedUnfairLock` so this compiles for every ChessCore platform.
nonisolated private final class LegalMovesCache: @unchecked Sendable {
    nonisolated static let shared = LegalMovesCache()
    private let lock = NSLock()
    private var storage: [String: [Move]] = [:]
    private let countLimit = 8192

    func get(_ key: String) -> [Move]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ key: String, _ value: [Move]) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count >= countLimit {
            // Drop ~10% of entries. Cheap O(k) eviction beats true LRU
            // bookkeeping for a workload dominated by hot positions.
            let toRemove = max(1, storage.count / 10)
            for key in storage.keys.prefix(toRemove) {
                storage.removeValue(forKey: key)
            }
        }
        storage[key] = value
    }
}

public nonisolated enum MoveGenerator {

    private static let rookDirections = [(0, 1), (0, -1), (1, 0), (-1, 0)]
    private static let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let queenDirections = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let knightOffsets = [
        (1, 2), (2, 1), (2, -1), (1, -2),
        (-1, -2), (-2, -1), (-2, 1), (-1, 2),
    ]

    // MARK: - Public API

    public static func legalMoves(for position: Position) -> [Move] {
        let key = position.positionKey
        if let cached = LegalMovesCache.shared.get(key) { return cached }
        let result = pseudoLegalMoves(for: position).filter { move in
            var newPos = position
            applyMoveUnchecked(&newPos, move)
            let kingSquare = findKing(in: newPos, color: position.activeColor)
            return !isSquareAttacked(kingSquare, by: position.activeColor.opposite, in: newPos)
        }
        LegalMovesCache.shared.set(key, result)
        return result
    }

    public static func findLegalMoves(for position: Position, piece: PieceType, to target: Square) -> [Move] {
        var candidates: [Move] = []
        for index in 0..<64 {
            let square = Square.fromIndex(index)
            guard let p = position[square], p.color == position.activeColor, p.type == piece else { continue }
            switch piece {
            case .pawn: pawnMoves(from: square, in: position, into: &candidates)
            case .knight: knightMoves(from: square, in: position, into: &candidates)
            case .bishop: slidingMoves(from: square, directions: bishopDirections, in: position, into: &candidates)
            case .rook: slidingMoves(from: square, directions: rookDirections, in: position, into: &candidates)
            case .queen: slidingMoves(from: square, directions: queenDirections, in: position, into: &candidates)
            case .king: kingMoves(from: square, in: position, into: &candidates)
            }
        }
        return candidates.filter { move in
            guard move.to == target else { return false }
            var newPos = position
            applyMoveUnchecked(&newPos, move)
            let kingSquare = findKing(in: newPos, color: position.activeColor)
            return !isSquareAttacked(kingSquare, by: position.activeColor.opposite, in: newPos)
        }
    }

    public static func hasAnyLegalMove(for position: Position) -> Bool {
        var moves: [Move] = []
        moves.reserveCapacity(32)
        for index in 0..<64 {
            let square = Square.fromIndex(index)
            guard let piece = position[square], piece.color == position.activeColor else { continue }
            moves.removeAll(keepingCapacity: true)
            switch piece.type {
            case .pawn: pawnMoves(from: square, in: position, into: &moves)
            case .knight: knightMoves(from: square, in: position, into: &moves)
            case .bishop: slidingMoves(from: square, directions: bishopDirections, in: position, into: &moves)
            case .rook: slidingMoves(from: square, directions: rookDirections, in: position, into: &moves)
            case .queen: slidingMoves(from: square, directions: queenDirections, in: position, into: &moves)
            case .king: kingMoves(from: square, in: position, into: &moves)
            }
            for move in moves {
                var newPos = position
                applyMoveUnchecked(&newPos, move)
                let kingSquare = findKing(in: newPos, color: position.activeColor)
                if !isSquareAttacked(kingSquare, by: position.activeColor.opposite, in: newPos) {
                    return true
                }
            }
        }
        return false
    }

    public static func isInCheck(_ position: Position) -> Bool {
        let kingSquare = findKing(in: position, color: position.activeColor)
        return isSquareAttacked(kingSquare, by: position.activeColor.opposite, in: position)
    }

    public static func applyMoveUnchecked(_ position: inout Position, _ move: Move) {
        guard let piece = position[move.from] else { return }

        position[move.to] = piece
        position[move.from] = nil

        if let promoType = move.promotion {
            position[move.to] = Piece(type: promoType, color: piece.color)
        }

        if move.isEnPassant {
            let capturedRank = piece.color == .white ? move.to.rank - 1 : move.to.rank + 1
            position[Square(file: move.to.file, rank: capturedRank)] = nil
        }

        if move.isCastling {
            let rank = move.to.rank
            if move.to.file == 6 {
                position[Square(file: 5, rank: rank)] = position[Square(file: 7, rank: rank)]
                position[Square(file: 7, rank: rank)] = nil
            } else if move.to.file == 2 {
                position[Square(file: 3, rank: rank)] = position[Square(file: 0, rank: rank)]
                position[Square(file: 0, rank: rank)] = nil
            }
        }

        if piece.type == .pawn && abs(move.to.rank - move.from.rank) == 2 {
            position.enPassantTarget = Square(
                file: move.from.file,
                rank: (move.from.rank + move.to.rank) / 2
            )
        } else {
            position.enPassantTarget = nil
        }

        if piece.type == .king {
            if piece.color == .white {
                position.whiteKingSquare = move.to
                position.castlingRights.whiteKingside = false
                position.castlingRights.whiteQueenside = false
            } else {
                position.blackKingSquare = move.to
                position.castlingRights.blackKingside = false
                position.castlingRights.blackQueenside = false
            }
        }

        if piece.type == .rook {
            switch move.from {
            case Square(file: 0, rank: 0): position.castlingRights.whiteQueenside = false
            case Square(file: 7, rank: 0): position.castlingRights.whiteKingside = false
            case Square(file: 0, rank: 7): position.castlingRights.blackQueenside = false
            case Square(file: 7, rank: 7): position.castlingRights.blackKingside = false
            default: break
            }
        }

        // Rook captured on its home square
        switch move.to {
        case Square(file: 0, rank: 0): position.castlingRights.whiteQueenside = false
        case Square(file: 7, rank: 0): position.castlingRights.whiteKingside = false
        case Square(file: 0, rank: 7): position.castlingRights.blackQueenside = false
        case Square(file: 7, rank: 7): position.castlingRights.blackKingside = false
        default: break
        }

        if piece.type == .pawn || move.capturedPiece != nil {
            position.halfmoveClock = 0
        } else {
            position.halfmoveClock += 1
        }

        if piece.color == .black {
            position.fullmoveNumber += 1
        }

        position.activeColor = position.activeColor.opposite
    }

    public static func algebraicNotation(for move: Move, in position: Position, legalMoves allLegal: [Move]? = nil) -> String {
        if move.isCastling {
            return move.to.file == 6 ? "O-O" : "O-O-O"
        }

        var notation = ""

        if move.piece != .pawn {
            notation += pieceSymbol(move.piece)

            let ambiguous: [Move]
            if let allLegal {
                ambiguous = allLegal.filter { m in
                    m.piece == move.piece && m.to == move.to && m.from != move.from
                }
            } else {
                ambiguous = findLegalMoves(for: position, piece: move.piece, to: move.to)
                    .filter { $0.from != move.from }
            }

            if !ambiguous.isEmpty {
                let sameFile = ambiguous.contains { $0.from.file == move.from.file }
                let sameRank = ambiguous.contains { $0.from.rank == move.from.rank }

                if !sameFile {
                    notation += String(move.from.fileChar)
                } else if !sameRank {
                    notation += "\(move.from.rank + 1)"
                } else {
                    notation += move.from.algebraic
                }
            }
        }

        if move.capturedPiece != nil {
            if move.piece == .pawn {
                notation += String(move.from.fileChar)
            }
            notation += "x"
        }

        notation += move.to.algebraic

        if let promo = move.promotion {
            notation += "=\(pieceSymbol(promo))"
        }

        var newPos = position
        applyMoveUnchecked(&newPos, move)
        if isSquareAttacked(findKing(in: newPos, color: newPos.activeColor), by: position.activeColor, in: newPos) {
            notation += hasAnyLegalMove(for: newPos) ? "+" : "#"
        }

        return notation
    }

    // MARK: - Pseudo-Legal Move Generation

    private static func pseudoLegalMoves(for position: Position) -> [Move] {
        var moves: [Move] = []
        for index in 0..<64 {
            let square = Square.fromIndex(index)
            guard let piece = position[square], piece.color == position.activeColor else { continue }
            switch piece.type {
            case .pawn: pawnMoves(from: square, in: position, into: &moves)
            case .knight: knightMoves(from: square, in: position, into: &moves)
            case .bishop: slidingMoves(from: square, directions: bishopDirections, in: position, into: &moves)
            case .rook: slidingMoves(from: square, directions: rookDirections, in: position, into: &moves)
            case .queen: slidingMoves(from: square, directions: queenDirections, in: position, into: &moves)
            case .king: kingMoves(from: square, in: position, into: &moves)
            }
        }
        return moves
    }

    private static func pawnMoves(from square: Square, in position: Position, into moves: inout [Move]) {
        let color = position[square]!.color
        let direction = color == .white ? 1 : -1
        let startRank = color == .white ? 1 : 6
        let promotionRank = color == .white ? 7 : 0

        let oneForward = Square(file: square.file, rank: square.rank + direction)
        if oneForward.isValid && position[oneForward] == nil {
            if oneForward.rank == promotionRank {
                for promoType in [PieceType.queen, .rook, .bishop, .knight] {
                    moves.append(Move(from: square, to: oneForward, piece: .pawn, promotion: promoType))
                }
            } else {
                moves.append(Move(from: square, to: oneForward, piece: .pawn))
            }

            if square.rank == startRank {
                let twoForward = Square(file: square.file, rank: square.rank + 2 * direction)
                if twoForward.isValid && position[twoForward] == nil {
                    moves.append(Move(from: square, to: twoForward, piece: .pawn))
                }
            }
        }

        for df in [-1, 1] {
            let capSquare = Square(file: square.file + df, rank: square.rank + direction)
            guard capSquare.isValid else { continue }

            if let target = position[capSquare], target.color != color {
                if capSquare.rank == promotionRank {
                    for promoType in [PieceType.queen, .rook, .bishop, .knight] {
                        moves.append(Move(
                            from: square, to: capSquare, piece: .pawn,
                            capturedPiece: target.type, promotion: promoType
                        ))
                    }
                } else {
                    moves.append(Move(from: square, to: capSquare, piece: .pawn, capturedPiece: target.type))
                }
            }

            if capSquare == position.enPassantTarget {
                moves.append(Move(
                    from: square, to: capSquare, piece: .pawn,
                    capturedPiece: .pawn, isEnPassant: true
                ))
            }
        }
    }

    private static func knightMoves(from square: Square, in position: Position, into moves: inout [Move]) {
        let color = position[square]!.color

        for offset in knightOffsets {
            let to = Square(file: square.file + offset.0, rank: square.rank + offset.1)
            guard to.isValid else { continue }
            if let target = position[to] {
                if target.color != color {
                    moves.append(Move(from: square, to: to, piece: .knight, capturedPiece: target.type))
                }
            } else {
                moves.append(Move(from: square, to: to, piece: .knight))
            }
        }
    }

    private static func slidingMoves(
        from square: Square,
        directions: [(Int, Int)],
        in position: Position,
        into moves: inout [Move]
    ) {
        let color = position[square]!.color
        let pieceType = position[square]!.type

        for dir in directions {
            for dist in 1..<8 {
                let to = Square(file: square.file + dir.0 * dist, rank: square.rank + dir.1 * dist)
                guard to.isValid else { break }
                if let target = position[to] {
                    if target.color != color {
                        moves.append(Move(from: square, to: to, piece: pieceType, capturedPiece: target.type))
                    }
                    break
                }
                moves.append(Move(from: square, to: to, piece: pieceType))
            }
        }
    }

    private static func kingMoves(from square: Square, in position: Position, into moves: inout [Move]) {
        let color = position[square]!.color

        for df in -1...1 {
            for dr in -1...1 {
                if df == 0 && dr == 0 { continue }
                let to = Square(file: square.file + df, rank: square.rank + dr)
                guard to.isValid else { continue }
                if let target = position[to] {
                    if target.color != color {
                        moves.append(Move(from: square, to: to, piece: .king, capturedPiece: target.type))
                    }
                } else {
                    moves.append(Move(from: square, to: to, piece: .king))
                }
            }
        }

        let rank = color == .white ? 0 : 7
        guard square == Square(file: 4, rank: rank) else { return }

        let kingsideRight = color == .white
            ? position.castlingRights.whiteKingside
            : position.castlingRights.blackKingside
        let queensideRight = color == .white
            ? position.castlingRights.whiteQueenside
            : position.castlingRights.blackQueenside

        if kingsideRight {
            let f = Square(file: 5, rank: rank)
            let g = Square(file: 6, rank: rank)
            if position[f] == nil && position[g] == nil
                && !isSquareAttacked(square, by: color.opposite, in: position)
                && !isSquareAttacked(f, by: color.opposite, in: position)
                && !isSquareAttacked(g, by: color.opposite, in: position)
            {
                moves.append(Move(from: square, to: g, piece: .king, isCastling: true))
            }
        }

        if queensideRight {
            let d = Square(file: 3, rank: rank)
            let c = Square(file: 2, rank: rank)
            let b = Square(file: 1, rank: rank)
            if position[d] == nil && position[c] == nil && position[b] == nil
                && !isSquareAttacked(square, by: color.opposite, in: position)
                && !isSquareAttacked(d, by: color.opposite, in: position)
                && !isSquareAttacked(c, by: color.opposite, in: position)
            {
                moves.append(Move(from: square, to: c, piece: .king, isCastling: true))
            }
        }
    }

    // MARK: - Helpers

    public static func findKing(in position: Position, color: PieceColor) -> Square {
        color == .white ? position.whiteKingSquare : position.blackKingSquare
    }

    public static func isSquareAttacked(_ square: Square, by color: PieceColor, in position: Position) -> Bool {
        for offset in knightOffsets {
            let sq = Square(file: square.file + offset.0, rank: square.rank + offset.1)
            if sq.isValid, let piece = position[sq], piece.color == color, piece.type == .knight {
                return true
            }
        }

        let pawnDir = color == .white ? -1 : 1
        for df in [-1, 1] {
            let sq = Square(file: square.file + df, rank: square.rank + pawnDir)
            if sq.isValid, let piece = position[sq], piece.color == color, piece.type == .pawn {
                return true
            }
        }

        for df in -1...1 {
            for dr in -1...1 {
                if df == 0 && dr == 0 { continue }
                let sq = Square(file: square.file + df, rank: square.rank + dr)
                if sq.isValid, let piece = position[sq], piece.color == color, piece.type == .king {
                    return true
                }
            }
        }

        for dir in rookDirections {
            for dist in 1..<8 {
                let sq = Square(file: square.file + dir.0 * dist, rank: square.rank + dir.1 * dist)
                guard sq.isValid else { break }
                if let piece = position[sq] {
                    if piece.color == color && (piece.type == .rook || piece.type == .queen) {
                        return true
                    }
                    break
                }
            }
        }

        for dir in bishopDirections {
            for dist in 1..<8 {
                let sq = Square(file: square.file + dir.0 * dist, rank: square.rank + dir.1 * dist)
                guard sq.isValid else { break }
                if let piece = position[sq] {
                    if piece.color == color && (piece.type == .bishop || piece.type == .queen) {
                        return true
                    }
                    break
                }
            }
        }

        return false
    }

    private static func pieceSymbol(_ type: PieceType) -> String {
        switch type {
        case .king: "K"
        case .queen: "Q"
        case .rook: "R"
        case .bishop: "B"
        case .knight: "N"
        case .pawn: ""
        }
    }
}
