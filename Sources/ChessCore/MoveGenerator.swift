import Foundation

public nonisolated enum MoveGenerator {

    // MARK: - Public API

    /// All legal moves for the side to move.
    ///
    /// Generation runs entirely on magic bitboards (see `MagicBitboards.swift`):
    /// a `BitBoard` view is built from the position, pseudo-legal moves are
    /// produced via the precomputed king/knight/pawn and magic rook/bishop
    /// attack tables, and each is verified by a cheap inline (stack) make +
    /// king-attack test. This is fast enough (~5.5x the old mailbox walker, and
    /// >5x faster than building+hashing a `positionKey` string) that the former
    /// `positionKey`-keyed result cache is gone — regenerating is now cheaper
    /// than the cache's string key, so the cache was a net pessimization.
    public static func legalMoves(for position: Position) -> [Move] {
        var board = BitBoard(position)
        return board.legalMoves()
    }

    public static func findLegalMoves(for position: Position, piece: PieceType, to target: Square) -> [Move] {
        // Filter the full legal-move list. Behaviorally identical to generating
        // per-piece pseudo-legal moves and filtering, but reuses the cached,
        // magic-bitboard legal generator.
        legalMoves(for: position).filter { $0.piece == piece && $0.to == target }
    }

    public static func hasAnyLegalMove(for position: Position) -> Bool {
        var board = BitBoard(position)
        return board.hasAnyLegalMove()
    }

    public static func isInCheck(_ position: Position) -> Bool {
        let board = BitBoard(position)
        let kingSq = position.activeColor == .white ? position.whiteKingSquare.index
                                                    : position.blackKingSquare.index
        return board.isAttacked(square: kingSq, by: position.activeColor.opposite)
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

    // MARK: - Helpers

    public static func findKing(in position: Position, color: PieceColor) -> Square {
        color == .white ? position.whiteKingSquare : position.blackKingSquare
    }

    /// Whether `square` is attacked by any `color` piece in `position`.
    /// Public API preserved; computed via magic bitboards.
    public static func isSquareAttacked(_ square: Square, by color: PieceColor, in position: Position) -> Bool {
        guard square.isValid else { return false }
        let board = BitBoard(position)
        return board.isAttacked(square: square.index, by: color)
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

// MARK: - Bitboard representation + generation

/// Inline (value-type, stack-allocated) store for the twelve piece bitboards —
/// `[color][type]` flattened to `color * 6 + type` — backed by a homogeneous
/// tuple so it carries NO heap allocation and NO ARC traffic. Building and
/// copying a `Boards12` is a handful of register/stack moves, which is what
/// makes the per-node `isLegal` make/unmake cheap. (A nested `[[UInt64]]` here
/// was the bottleneck in the first cut: a heap alloc per node + deep copy per
/// legality test.) Index access goes through an unsafe pointer over the tuple —
/// a well-defined Swift pattern for fixed homogeneous tuples.
struct Boards12 {
    var storage: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                  UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    @inline(__always) subscript(_ i: Int) -> UInt64 {
        get {
            withUnsafeBytes(of: storage) {
                $0.baseAddress!.assumingMemoryBound(to: UInt64.self)[i]
            }
        }
        set {
            withUnsafeMutableBytes(of: &storage) {
                $0.baseAddress!.assumingMemoryBound(to: UInt64.self)[i] = newValue
            }
        }
    }

    /// `pieces[color][type]` accessor: color 0/1, type 0…5.
    @inline(__always) subscript(_ color: Int, _ type: Int) -> UInt64 {
        get { self[color * 6 + type] }
        set { self[color * 6 + type] = newValue }
    }
}

/// A dense bitboard view of a `Position`, built once per `legalMoves(for:)`
/// call. All move generation and legality checks run on these bitboards via the
/// magic attack tables; the produced `[Move]` carries the exact same fields
/// (capturedPiece, promotion, isEnPassant, isCastling) the mailbox generator
/// produced, so every public consumer and the perft oracle see identical moves.
struct BitBoard {
    // Piece bitboards indexed [color][pieceType] via `Boards12`.
    //   color: 0 = white, 1 = black
    //   type:  0=king 1=queen 2=rook 3=bishop 4=knight 5=pawn
    var pieces = Boards12()
    var occWhite: Bitboard = 0
    var occBlack: Bitboard = 0
    var allOcc: Bitboard = 0

    let side: Int            // 0 = white to move, 1 = black
    let castling: CastlingRights
    let epSquare: Int        // en-passant target square index, or -1

    static let m = Magics.shared

    @inline(__always) func occ(_ c: Int) -> Bitboard { c == 0 ? occWhite : occBlack }

    @inline(__always) static func typeIndex(_ t: PieceType) -> Int {
        switch t {
        case .king: 0
        case .queen: 1
        case .rook: 2
        case .bishop: 3
        case .knight: 4
        case .pawn: 5
        }
    }

    @inline(__always) static func typeFor(_ i: Int) -> PieceType {
        switch i {
        case 0: .king
        case 1: .queen
        case 2: .rook
        case 3: .bishop
        case 4: .knight
        default: .pawn
        }
    }

    init(_ position: Position) {
        self.side = position.activeColor == .white ? 0 : 1
        self.castling = position.castlingRights
        self.epSquare = position.enPassantTarget?.index ?? -1

        let board = position.board
        var pieces = Boards12()
        var occW: Bitboard = 0
        var occB: Bitboard = 0
        for i in 0..<64 {
            guard let p = board[i] else { continue }
            let c = p.color == .white ? 0 : 1
            let t = BitBoard.typeIndex(p.type)
            pieces[c, t] |= bit(i)
            if c == 0 { occW |= bit(i) } else { occB |= bit(i) }
        }
        self.pieces = pieces
        self.occWhite = occW
        self.occBlack = occB
        self.allOcc = occW | occB
    }

    // MARK: Attack queries

    /// Is `square` attacked by any piece of `color` (0=white, 1=black)?
    func isAttacked(square: Int, by color: PieceColor) -> Bool {
        let c = color == .white ? 0 : 1
        return squareAttacked(square, byColor: c, pieces: pieces, occAll: allOcc)
    }

    // MARK: Legal move generation

    mutating func legalMoves() -> [Move] {
        var pseudo: [Move] = []
        pseudo.reserveCapacity(48)
        generatePseudoLegal(into: &pseudo)

        var legal: [Move] = []
        legal.reserveCapacity(pseudo.count)
        for move in pseudo where isLegal(move) {
            legal.append(move)
        }
        return legal
    }

    mutating func hasAnyLegalMove() -> Bool {
        var pseudo: [Move] = []
        pseudo.reserveCapacity(48)
        generatePseudoLegal(into: &pseudo)
        for move in pseudo where isLegal(move) {
            return true
        }
        return false
    }

    /// Make `move` on an inline (stack) copy of the bitboards and check whether
    /// the mover's king is left in check. Castling legality (path squares not
    /// attacked) is enforced at generation time, matching the mailbox code.
    func isLegal(_ move: Move) -> Bool {
        var pieces = self.pieces        // cheap value copy (no heap / ARC)
        var occAll = self.allOcc

        let us = side
        let them = us ^ 1
        let fromI = move.from.index
        let toI = move.to.index
        let pType = BitBoard.typeIndex(move.piece)

        // Remove mover from origin.
        pieces[us, pType] &= ~bit(fromI)
        occAll &= ~bit(fromI)

        // Remove captured piece (en passant captures off the destination file).
        if move.isEnPassant {
            let capRank = us == 0 ? (toI / 8) - 1 : (toI / 8) + 1
            let capSq = capRank * 8 + (toI % 8)
            pieces[them, 5] &= ~bit(capSq)
            occAll &= ~bit(capSq)
        } else if let captured = move.capturedPiece {
            let capT = BitBoard.typeIndex(captured)
            pieces[them, capT] &= ~bit(toI)
            occAll &= ~bit(toI)
        }

        // Place mover (promotion swaps the type) at destination.
        if let promo = move.promotion {
            pieces[us, BitBoard.typeIndex(promo)] |= bit(toI)
        } else {
            pieces[us, pType] |= bit(toI)
        }
        occAll |= bit(toI)

        // Move the rook for castling so its new square is considered.
        if move.isCastling {
            let rank = toI / 8
            if toI % 8 == 6 { // kingside: h-rook -> f
                let rookFrom = rank * 8 + 7
                let rookTo = rank * 8 + 5
                pieces[us, 2] &= ~bit(rookFrom)
                pieces[us, 2] |= bit(rookTo)
                occAll &= ~bit(rookFrom)
                occAll |= bit(rookTo)
            } else if toI % 8 == 2 { // queenside: a-rook -> d
                let rookFrom = rank * 8 + 0
                let rookTo = rank * 8 + 3
                pieces[us, 2] &= ~bit(rookFrom)
                pieces[us, 2] |= bit(rookTo)
                occAll &= ~bit(rookFrom)
                occAll |= bit(rookTo)
            }
        }

        let kingSq = lsbIndex(pieces[us, 0])
        return !squareAttacked(kingSq, byColor: them, pieces: pieces, occAll: occAll)
    }

    /// Attack test against an arbitrary (post-move) bitboard set.
    @inline(__always)
    private func squareAttacked(_ square: Int, byColor c: Int, pieces: Boards12, occAll: Bitboard) -> Bool {
        let m = BitBoard.m
        let opp = c ^ 1
        if m.pawnAttacks(square, color: opp) & pieces[c, 5] != 0 { return true }
        if m.knightAttacks(square) & pieces[c, 4] != 0 { return true }
        if m.kingAttacks(square) & pieces[c, 0] != 0 { return true }
        let queens = pieces[c, 1]
        if m.rookAttacks(square, occupancy: occAll) & (pieces[c, 2] | queens) != 0 { return true }
        if m.bishopAttacks(square, occupancy: occAll) & (pieces[c, 3] | queens) != 0 { return true }
        return false
    }

    // MARK: Pseudo-legal generation

    /// Generate pseudo-legal moves in the same square-major order the mailbox
    /// generator used (iterate squares 0..63; emit the moves of any friendly
    /// piece there), so any consumer relying on ordering is unaffected.
    private func generatePseudoLegal(into moves: inout [Move]) {
        let us = side
        var remaining = occ(us)
        // Iterate friendly pieces by ascending square index.
        while remaining != 0 {
            let sq = popLSB(&remaining)
            let t = pieceTypeAt(sq, color: us)
            switch t {
            case 5: pawnMoves(from: sq, into: &moves)
            case 4: knightMoves(from: sq, into: &moves)
            case 3: sliderMoves(from: sq, pieceType: .bishop, attacks: BitBoard.m.bishopAttacks(sq, occupancy: allOcc), into: &moves)
            case 2: sliderMoves(from: sq, pieceType: .rook, attacks: BitBoard.m.rookAttacks(sq, occupancy: allOcc), into: &moves)
            case 1: sliderMoves(from: sq, pieceType: .queen, attacks: BitBoard.m.queenAttacks(sq, occupancy: allOcc), into: &moves)
            case 0: kingMoves(from: sq, into: &moves)
            default: break
            }
        }
    }

    @inline(__always) private func pieceTypeAt(_ sq: Int, color c: Int) -> Int {
        let b = bit(sq)
        if pieces[c, 5] & b != 0 { return 5 }
        if pieces[c, 4] & b != 0 { return 4 }
        if pieces[c, 3] & b != 0 { return 3 }
        if pieces[c, 2] & b != 0 { return 2 }
        if pieces[c, 1] & b != 0 { return 1 }
        return 0
    }

    /// Identify the captured piece type sitting on `sq` for the enemy color.
    @inline(__always) private func capturedTypeAt(_ sq: Int) -> PieceType? {
        let them = side ^ 1
        guard occ(them) & bit(sq) != 0 else { return nil }
        return BitBoard.typeFor(pieceTypeAt(sq, color: them))
    }

    private func pawnMoves(from sq: Int, into moves: inout [Move]) {
        let us = side
        let from = Square.fromIndex(sq)
        let file = sq % 8
        let rank = sq / 8
        let dir = us == 0 ? 1 : -1
        let startRank = us == 0 ? 1 : 6
        let promoRank = us == 0 ? 7 : 0
        let promoTypes: [PieceType] = [.queen, .rook, .bishop, .knight]

        // Single push.
        let oneRank = rank + dir
        if (0..<8).contains(oneRank) {
            let oneSq = oneRank * 8 + file
            if allOcc & bit(oneSq) == 0 {
                let to = Square.fromIndex(oneSq)
                if oneRank == promoRank {
                    for promo in promoTypes {
                        moves.append(Move(from: from, to: to, piece: .pawn, promotion: promo))
                    }
                } else {
                    moves.append(Move(from: from, to: to, piece: .pawn))
                }
                // Double push.
                if rank == startRank {
                    let twoSq = (rank + 2 * dir) * 8 + file
                    if allOcc & bit(twoSq) == 0 {
                        moves.append(Move(from: from, to: Square.fromIndex(twoSq), piece: .pawn))
                    }
                }
            }
        }

        // Captures (incl. en passant), file order -1 then +1 to match mailbox.
        for df in [-1, 1] {
            let cf = file + df
            guard (0..<8).contains(cf) else { continue }
            let cr = rank + dir
            guard (0..<8).contains(cr) else { continue }
            let capSq = cr * 8 + cf
            let to = Square.fromIndex(capSq)

            if let capturedType = capturedTypeAt(capSq) {
                if cr == promoRank {
                    for promo in promoTypes {
                        moves.append(Move(from: from, to: to, piece: .pawn,
                                          capturedPiece: capturedType, promotion: promo))
                    }
                } else {
                    moves.append(Move(from: from, to: to, piece: .pawn, capturedPiece: capturedType))
                }
            }

            if capSq == epSquare {
                moves.append(Move(from: from, to: to, piece: .pawn,
                                  capturedPiece: .pawn, isEnPassant: true))
            }
        }
    }

    private func knightMoves(from sq: Int, into moves: inout [Move]) {
        let from = Square.fromIndex(sq)
        var targets = BitBoard.m.knightAttacks(sq) & ~occ(side)
        while targets != 0 {
            let toI = popLSB(&targets)
            let captured = capturedTypeAt(toI)
            moves.append(Move(from: from, to: Square.fromIndex(toI), piece: .knight, capturedPiece: captured))
        }
    }

    private func sliderMoves(from sq: Int, pieceType: PieceType, attacks: Bitboard, into moves: inout [Move]) {
        let from = Square.fromIndex(sq)
        var targets = attacks & ~occ(side)
        while targets != 0 {
            let toI = popLSB(&targets)
            let captured = capturedTypeAt(toI)
            moves.append(Move(from: from, to: Square.fromIndex(toI), piece: pieceType, capturedPiece: captured))
        }
    }

    private func kingMoves(from sq: Int, into moves: inout [Move]) {
        let us = side
        let from = Square.fromIndex(sq)
        var targets = BitBoard.m.kingAttacks(sq) & ~occ(us)
        while targets != 0 {
            let toI = popLSB(&targets)
            let captured = capturedTypeAt(toI)
            moves.append(Move(from: from, to: Square.fromIndex(toI), piece: .king, capturedPiece: captured))
        }

        // Castling — only from the king's home square, mirroring the mailbox
        // generator (path empty + king/transit squares not attacked).
        let homeRank = us == 0 ? 0 : 7
        guard sq == homeRank * 8 + 4 else { return }
        let them = us ^ 1

        let kingside = us == 0 ? castling.whiteKingside : castling.blackKingside
        let queenside = us == 0 ? castling.whiteQueenside : castling.blackQueenside

        if kingside {
            let fSq = homeRank * 8 + 5
            let gSq = homeRank * 8 + 6
            if allOcc & bit(fSq) == 0 && allOcc & bit(gSq) == 0
                && !isAttackedIdx(sq, by: them)
                && !isAttackedIdx(fSq, by: them)
                && !isAttackedIdx(gSq, by: them) {
                moves.append(Move(from: from, to: Square.fromIndex(gSq), piece: .king, isCastling: true))
            }
        }

        if queenside {
            let dSq = homeRank * 8 + 3
            let cSq = homeRank * 8 + 2
            let bSq = homeRank * 8 + 1
            if allOcc & bit(dSq) == 0 && allOcc & bit(cSq) == 0 && allOcc & bit(bSq) == 0
                && !isAttackedIdx(sq, by: them)
                && !isAttackedIdx(dSq, by: them)
                && !isAttackedIdx(cSq, by: them) {
                moves.append(Move(from: from, to: Square.fromIndex(cSq), piece: .king, isCastling: true))
            }
        }
    }

    /// Attack test on the current (pre-move) bitboards, by color index.
    @inline(__always) private func isAttackedIdx(_ square: Int, by c: Int) -> Bool {
        squareAttacked(square, byColor: c, pieces: pieces, occAll: allOcc)
    }
}
