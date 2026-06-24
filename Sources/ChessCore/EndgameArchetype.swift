import Foundation

/// Procedural endgame-archetype generator. Each case produces a random
/// legal FEN matching its training theme so the trainer has unlimited
/// replay value — the user sees a fresh position every time they revisit
/// the same drill, instead of memorising a single hard-coded layout.
///
/// "Legal" here means *playable* — the side not to move isn't in check,
/// the side to move has at least one legal move, and the position passes
/// the obvious sanity rules (kings not adjacent, pawns not on the back
/// ranks, etc.). The tablebase service is still the authority on whether
/// a specific move maintains the win; the generator just guarantees a
/// reasonable starting position.
public nonisolated enum EndgameArchetype: String, Hashable, Codable, Sendable, CaseIterable {
    case kqVsK
    case krVsK
    case k2bVsK
    case kbnVsK
    case kpVsK
    case kqVsKp
    case lucena
    case philidor

    public var displayCategory: String {
        switch self {
        case .kqVsK: "K+Q vs K"
        case .krVsK: "K+R vs K"
        case .k2bVsK: "K+2B vs K"
        case .kbnVsK: "K+B+N vs K"
        case .kpVsK: "K+P vs K"
        case .kqVsKp: "K+Q vs K+P"
        case .lucena: "Lucena"
        case .philidor: "Philidor"
        }
    }

    /// Produce a random legal FEN matching this archetype. Falls back to a
    /// known-good static FEN if random generation can't satisfy the
    /// constraints after enough retries (in practice the loop succeeds on
    /// the first attempt for the simple archetypes).
    public func randomFEN() -> String {
        for _ in 0..<200 {
            if let fen = attemptGenerate() {
                return fen
            }
        }
        return fallbackFEN
    }

    /// Known-good static position used when random generation fails. These
    /// are the same FENs the trainer used before the procedural generator
    /// landed, with the three previously-illegal positions fixed.
    public var fallbackFEN: String {
        switch self {
        case .kqVsK:    "8/8/8/4k3/8/3Q4/3K4/8 w - - 0 1"
        case .krVsK:    "8/8/8/4k3/8/4K3/8/4R3 w - - 0 1"
        case .k2bVsK:   "8/8/8/4k3/8/4K3/8/3BB3 w - - 0 1"
        case .kbnVsK:   "8/8/8/4k3/8/4K3/3B4/4N3 w - - 0 1"
        case .kpVsK:    "8/8/8/4k3/4P3/4K3/8/8 w - - 0 1"
        case .kqVsKp:   "8/8/8/8/8/1k1p4/3Q4/3K4 w - - 0 1"
        case .lucena:   "1K6/1P1k4/8/8/8/8/r7/2R5 w - - 0 1"
        case .philidor: "8/8/4k3/8/4K3/r7/4P3/3R4 b - - 0 1"
        }
    }

    private func attemptGenerate() -> String? {
        switch self {
        case .kqVsK:    return Self.generateKQvsK()
        case .krVsK:    return Self.generateKRvsK()
        case .k2bVsK:   return Self.generateK2BvsK()
        case .kbnVsK:   return Self.generateKBNvsK()
        case .kpVsK:    return Self.generateKPvsK()
        case .kqVsKp:   return Self.generateKQvsKp()
        case .lucena:   return Self.generateLucena()
        case .philidor: return Self.generatePhilidor()
        }
    }

    // MARK: - Generators

    private static func generateKQvsK() -> String? {
        let bk = randomCentralSquare()
        guard let wk = randomSquare(distinctFrom: [bk], kingAdjacentForbiddenTo: [bk], inDistanceRange: 2...4, of: bk) else { return nil }
        guard let wq = randomSquare(distinctFrom: [bk, wk], notEnPrise: bk, defendedBy: wk) else { return nil }

        var pos = Position()
        place(.king, .black, at: bk, in: &pos)
        place(.king, .white, at: wk, in: &pos)
        place(.queen, .white, at: wq, in: &pos)
        pos.activeColor = .white
        return finalize(pos)
    }

    private static func generateKRvsK() -> String? {
        let bk = randomCentralSquare()
        guard let wk = randomSquare(distinctFrom: [bk], kingAdjacentForbiddenTo: [bk], inDistanceRange: 2...4, of: bk) else { return nil }
        guard let wr = randomSquare(distinctFrom: [bk, wk], notEnPrise: bk, defendedBy: wk) else { return nil }

        var pos = Position()
        place(.king, .black, at: bk, in: &pos)
        place(.king, .white, at: wk, in: &pos)
        place(.rook, .white, at: wr, in: &pos)
        pos.activeColor = .white
        return finalize(pos)
    }

    private static func generateK2BvsK() -> String? {
        let bk = randomCornerwardSquare()
        guard let wk = randomSquare(distinctFrom: [bk], kingAdjacentForbiddenTo: [bk], inDistanceRange: 2...5, of: bk) else { return nil }
        guard let bLight = randomSquareOfColor(.light, distinctFrom: [bk, wk]) else { return nil }
        guard let bDark = randomSquareOfColor(.dark, distinctFrom: [bk, wk, bLight]) else { return nil }

        var pos = Position()
        place(.king, .black, at: bk, in: &pos)
        place(.king, .white, at: wk, in: &pos)
        place(.bishop, .white, at: bLight, in: &pos)
        place(.bishop, .white, at: bDark, in: &pos)
        pos.activeColor = .white
        return finalize(pos)
    }

    private static func generateKBNvsK() -> String? {
        let bk = randomCornerwardSquare()
        guard let wk = randomSquare(distinctFrom: [bk], kingAdjacentForbiddenTo: [bk], inDistanceRange: 2...5, of: bk) else { return nil }
        // Pick a bishop colour and a matching corner — the B+N mate only
        // works against the bishop's colour corner, so the bishop's square
        // determines the drill's solution direction.
        let bishopColor: SquareColor = Bool.random() ? .light : .dark
        guard let bishop = randomSquareOfColor(bishopColor, distinctFrom: [bk, wk]) else { return nil }
        guard let knight = randomSquare(distinctFrom: [bk, wk, bishop]) else { return nil }

        var pos = Position()
        place(.king, .black, at: bk, in: &pos)
        place(.king, .white, at: wk, in: &pos)
        place(.bishop, .white, at: bishop, in: &pos)
        place(.knight, .white, at: knight, in: &pos)
        pos.activeColor = .white
        return finalize(pos)
    }

    private static func generateKPvsK() -> String? {
        // Pawn on rank 3-6 keeps the position both winnable (white has room
        // to escort) and non-trivial (not one move from promotion).
        let pawnRank = Int.random(in: 2...5)
        let pawnFile = Int.random(in: 0..<8)
        let pawn = Square(file: pawnFile, rank: pawnRank)

        // White king close to or in front of the pawn — classic K+P shapes.
        guard let wk = randomSquare(
            distinctFrom: [pawn],
            inDistanceRange: 1...2,
            of: Square(file: pawnFile, rank: pawnRank + 1)
        ) else { return nil }
        guard wk.rank > 0 else { return nil }   // never on rank 1

        // Black king somewhere blocking-ish, 2-4 squares away, not adjacent
        // to white king, not adjacent to pawn (would be en prise).
        guard let bk = randomSquare(
            distinctFrom: [pawn, wk],
            kingAdjacentForbiddenTo: [wk],
            inDistanceRange: 2...4,
            of: pawn
        ) else { return nil }
        guard !pawnAttacks(from: pawn, color: .white).contains(bk) else { return nil }

        var pos = Position()
        place(.king, .black, at: bk, in: &pos)
        place(.king, .white, at: wk, in: &pos)
        place(.pawn, .white, at: pawn, in: &pos)
        pos.activeColor = .white
        return finalize(pos)
    }

    private static func generateKQvsKp() -> String? {
        // Black pawn on rank 2-3 (close to queening) — the drill is for
        // white to stop it. Generated with white to move so the user
        // immediately decides how to block.
        let pawnRank = Int.random(in: 1...2)  // black pawn promotes on rank 0
        let pawnFile = Int.random(in: 0..<8)
        let pawn = Square(file: pawnFile, rank: pawnRank)

        let bk = randomCentralSquare()
        guard bk != pawn else { return nil }
        guard let wk = randomSquare(distinctFrom: [pawn, bk], kingAdjacentForbiddenTo: [bk], inDistanceRange: 2...5, of: pawn) else { return nil }
        guard let wq = randomSquare(distinctFrom: [pawn, bk, wk], notEnPrise: bk, defendedBy: wk) else { return nil }
        guard !pawnAttacks(from: pawn, color: .black).contains(wk) else { return nil }
        guard !pawnAttacks(from: pawn, color: .black).contains(wq) else { return nil }

        var pos = Position()
        place(.king, .black, at: bk, in: &pos)
        place(.king, .white, at: wk, in: &pos)
        place(.queen, .white, at: wq, in: &pos)
        place(.pawn, .black, at: pawn, in: &pos)
        pos.activeColor = .white
        return finalize(pos)
    }

    private static func generateLucena() -> String? {
        // Lucena position: white king on the 8th rank cornered with its
        // pawn on the 7th in front, black king alongside trying to keep
        // out, black rook cutting off, white rook ready to "build a
        // bridge". Vary the file (b/c sides on the queenside,
        // mirrored on the kingside) for replay value while preserving
        // the technique.
        let templates: [(wk: String, wp: String, bk: String, br: String, wr: String)] = [
            (wk: "b8", wp: "b7", bk: "d7", br: "a2", wr: "c1"),
            (wk: "c8", wp: "c7", bk: "e7", br: "a2", wr: "d1"),
            (wk: "g8", wp: "g7", bk: "e7", br: "h2", wr: "f1"),
            (wk: "f8", wp: "f7", bk: "d7", br: "h2", wr: "e1"),
            (wk: "b8", wp: "b7", bk: "d6", br: "a2", wr: "c1"),
        ]
        return positionFromTemplate(templates.randomElement()!, sideToMove: .white)
    }

    private static func generatePhilidor() -> String? {
        // Philidor position: defender (black) holds the 3rd rank with
        // their rook to stop white's king from advancing in front of
        // the pawn. Vary the file and which side defends.
        let templates: [(wk: String, wp: String, wr: String, bk: String, br: String)] = [
            (wk: "e4", wp: "e2", wr: "d1", bk: "e6", br: "a3"),
            (wk: "d4", wp: "d2", wr: "c1", bk: "d6", br: "h3"),
            (wk: "f4", wp: "f2", wr: "g1", bk: "f6", br: "a3"),
            (wk: "e4", wp: "e2", wr: "h1", bk: "e6", br: "a3"),
        ]
        return positionFromPhilidorTemplate(templates.randomElement()!)
    }

    // MARK: - Template helpers

    private static func positionFromTemplate(
        _ t: (wk: String, wp: String, bk: String, br: String, wr: String),
        sideToMove: PieceColor
    ) -> String? {
        guard let wk = Square(algebraic: t.wk),
              let wp = Square(algebraic: t.wp),
              let bk = Square(algebraic: t.bk),
              let br = Square(algebraic: t.br),
              let wr = Square(algebraic: t.wr) else { return nil }
        var pos = Position()
        place(.king, .white, at: wk, in: &pos)
        place(.pawn, .white, at: wp, in: &pos)
        place(.king, .black, at: bk, in: &pos)
        place(.rook, .black, at: br, in: &pos)
        place(.rook, .white, at: wr, in: &pos)
        pos.activeColor = sideToMove
        return finalize(pos)
    }

    private static func positionFromPhilidorTemplate(
        _ t: (wk: String, wp: String, wr: String, bk: String, br: String)
    ) -> String? {
        guard let wk = Square(algebraic: t.wk),
              let wp = Square(algebraic: t.wp),
              let wr = Square(algebraic: t.wr),
              let bk = Square(algebraic: t.bk),
              let br = Square(algebraic: t.br) else { return nil }
        var pos = Position()
        place(.king, .white, at: wk, in: &pos)
        place(.pawn, .white, at: wp, in: &pos)
        place(.rook, .white, at: wr, in: &pos)
        place(.king, .black, at: bk, in: &pos)
        place(.rook, .black, at: br, in: &pos)
        pos.activeColor = .black
        return finalize(pos)
    }

    // MARK: - Random-square primitives

    fileprivate static func randomCentralSquare() -> Square {
        Square(file: .random(in: 2...5), rank: .random(in: 2...5))
    }

    fileprivate static func randomCornerwardSquare() -> Square {
        // For drill archetypes that need the king pushable into a corner
        // (K+2B vs K, K+B+N vs K), start it nearer the edge so the user
        // has somewhere to chase it to.
        let files = [1, 2, 5, 6]
        let ranks = [1, 2, 5, 6]
        return Square(file: files.randomElement()!, rank: ranks.randomElement()!)
    }

    fileprivate static func randomSquare(
        distinctFrom occupied: [Square] = [],
        kingAdjacentForbiddenTo forbiddenAdjacent: [Square] = [],
        inDistanceRange range: ClosedRange<Int>? = nil,
        of anchor: Square? = nil,
        notEnPrise enemyKing: Square? = nil,
        defendedBy friendKing: Square? = nil,
        rankRange: ClosedRange<Int> = 0...7
    ) -> Square? {
        // Try up to 50 random picks; on failure the caller's outer retry
        // loop will repeat with a fresh anchor.
        for _ in 0..<50 {
            let sq = Square(file: .random(in: 0..<8), rank: .random(in: rankRange))
            if occupied.contains(sq) { continue }
            if forbiddenAdjacent.contains(where: { kingsAdjacent($0, sq) }) { continue }
            if let range, let anchor {
                let dist = chebyshevDistance(sq, anchor)
                if !range.contains(dist) { continue }
            }
            if let enemyKing, kingsAdjacent(enemyKing, sq) {
                // En prise: only defendable by own king being adjacent too.
                guard let friendKing, kingsAdjacent(friendKing, sq) else { continue }
            }
            return sq
        }
        return nil
    }

    fileprivate enum SquareColor { case light, dark }

    fileprivate static func randomSquareOfColor(_ color: SquareColor, distinctFrom occupied: [Square]) -> Square? {
        for _ in 0..<50 {
            let sq = Square(file: .random(in: 0..<8), rank: .random(in: 0..<8))
            if occupied.contains(sq) { continue }
            let isLight = (sq.file + sq.rank) % 2 != 0
            switch color {
            case .light where isLight: return sq
            case .dark where !isLight: return sq
            default: continue
            }
        }
        return nil
    }

    // MARK: - Geometry

    fileprivate static func kingsAdjacent(_ a: Square, _ b: Square) -> Bool {
        abs(a.file - b.file) <= 1 && abs(a.rank - b.rank) <= 1
    }

    fileprivate static func chebyshevDistance(_ a: Square, _ b: Square) -> Int {
        max(abs(a.file - b.file), abs(a.rank - b.rank))
    }

    fileprivate static func pawnAttacks(from square: Square, color: PieceColor) -> [Square] {
        let direction = color == .white ? 1 : -1
        let targetRank = square.rank + direction
        guard (0..<8).contains(targetRank) else { return [] }
        return [
            Square(file: square.file - 1, rank: targetRank),
            Square(file: square.file + 1, rank: targetRank)
        ].filter { (0..<8).contains($0.file) && (0..<8).contains($0.rank) }
    }

    // MARK: - Position assembly

    fileprivate static func place(_ type: PieceType, _ color: PieceColor, at square: Square, in pos: inout Position) {
        pos[square] = Piece(type: type, color: color)
        if type == .king {
            if color == .white { pos.whiteKingSquare = square }
            else { pos.blackKingSquare = square }
        }
    }

    fileprivate static func finalize(_ pos: Position) -> String? {
        // Side not to move must not be in check (would mean the previous
        // move was illegal — they put themselves into check).
        var flipped = pos
        flipped.activeColor = pos.activeColor.opposite
        guard !MoveGenerator.isInCheck(flipped) else { return nil }

        // Side to move must have at least one legal move — otherwise the
        // position is already mate or stalemate, which isn't a drill.
        guard !MoveGenerator.legalMoves(for: pos).isEmpty else { return nil }

        // Use the sanitised FEN accessor — `Position()` defaults castling
        // rights to all-true and random endgame layouts don't have the
        // kings/rooks on their home squares, which used to crash
        // Stockfish's strict parser when these FENs later reached it.
        // `stockfishSafeFEN` zeros castling/en-passant inconsistent with
        // the actual board state.
        return pos.stockfishSafeFEN
    }
}

// MARK: - Custom (user-defined) endgame configuration

/// User-defined endgame setup: pick how many of each non-king piece each
/// side has, then generate a random legal position with those pieces.
/// Useful for exploring positions outside the curated archetypes (e.g.
/// pawn-vs-pawn studies, or material imbalances that aren't a recognised
/// theoretical endgame). Positions with more than 7 pieces total fall
/// outside the Lichess tablebase, so the trainer will simply skip win
/// verification for them — the user just plays freely.
public nonisolated struct CustomEndgameConfig: Hashable, Sendable, Codable {
    public var white = PieceCounts()
    public var black = PieceCounts()

    public struct PieceCounts: Hashable, Sendable, Codable {
        var queens: Int = 0
        var rooks: Int = 0
        var bishops: Int = 0
        var knights: Int = 0
        var pawns: Int = 0

        var totalNonKing: Int { queens + rooks + bishops + knights + pawns }

        /// Returns "K+Q+R+P" / "K+2N+P" style summary — collapses multiples
        /// into "2N", "3P", etc., matching how endgame theory is usually
        /// written.
        var summary: String {
            PieceType.materialSummary([
                .queen: queens, .rook: rooks, .bishop: bishops,
                .knight: knights, .pawn: pawns
            ])
        }

        /// Material clamp: 9 queens / rooks etc. is silly, but we don't
        /// hard-cap below the legal-in-chess limit (which itself is fuzzy
        /// for promoted pieces). The picker UI keeps the per-piece step
        /// inside a reasonable range.
        static let maxPerPieceType = 4

        func clamped() -> PieceCounts {
            PieceCounts(
                queens: max(0, min(Self.maxPerPieceType, queens)),
                rooks: max(0, min(Self.maxPerPieceType, rooks)),
                bishops: max(0, min(Self.maxPerPieceType, bishops)),
                knights: max(0, min(Self.maxPerPieceType, knights)),
                pawns: max(0, min(8, pawns))
            )
        }
    }

    public var totalPieces: Int { 2 + white.totalNonKing + black.totalNonKing }

    /// e.g. "K+R+P vs K+B+N" — used in the picker preview and as the
    /// spaced-repetition key (custom configs don't share an SR slot
    /// with the curated catalogue).
    public var summary: String { "\(white.summary) vs \(black.summary)" }

    /// 32 is the practical ceiling (full chess board); the picker keeps us
    /// well under that, but cap defensively.
    public var isValid: Bool { totalPieces <= 32 }

    /// Generate a fresh legal position with the requested piece counts.
    /// Returns `nil` if 200 retries can't satisfy the constraints — for
    /// instance, requesting 8 pieces of the same colour bunched into a
    /// tight area is sometimes unsatisfiable.
    public func randomFEN() -> String? {
        for _ in 0..<200 {
            if let fen = attemptGenerate() {
                return fen
            }
        }
        return nil
    }

    /// Fallback when random generation can't satisfy the constraints —
    /// returns a trivial K vs K position so the trainer always has *some*
    /// board to show. The user can hit "Skip" / "Next" to roll again.
    public var fallbackFEN: String { "8/8/8/4k3/8/4K3/8/8 w - - 0 1" }

    private func attemptGenerate() -> String? {
        var pos = Position()
        var occupied: [Square] = []

        // Black king first — centralish so the position has somewhere
        // for white to attack from.
        let bk = EndgameArchetype.randomCentralSquare()
        EndgameArchetype.place(.king, .black, at: bk, in: &pos)
        occupied.append(bk)

        // White king: not adjacent to bk (no touching kings) and within a
        // reasonable distance so the position has board tension.
        guard let wk = EndgameArchetype.randomSquare(
            distinctFrom: occupied,
            kingAdjacentForbiddenTo: [bk]
        ) else { return nil }
        EndgameArchetype.place(.king, .white, at: wk, in: &pos)
        occupied.append(wk)

        // Place all remaining pieces with type-appropriate constraints.
        if !placePieces(white.clamped(), color: .white, kingOwn: wk, kingEnemy: bk, into: &pos, occupied: &occupied) {
            return nil
        }
        if !placePieces(black.clamped(), color: .black, kingOwn: bk, kingEnemy: wk, into: &pos, occupied: &occupied) {
            return nil
        }

        pos.activeColor = .white
        return EndgameArchetype.finalize(pos)
    }

    private func placePieces(
        _ counts: PieceCounts,
        color: PieceColor,
        kingOwn: Square,
        kingEnemy: Square,
        into pos: inout Position,
        occupied: inout [Square]
    ) -> Bool {
        // Pieces with no rank restriction; pawns are handled separately
        // because they can't sit on rank 0 or 7.
        let nonPawn: [(PieceType, Int)] = [
            (.queen, counts.queens),
            (.rook, counts.rooks),
            (.bishop, counts.bishops),
            (.knight, counts.knights)
        ]
        for (type, n) in nonPawn {
            for _ in 0..<n {
                guard let sq = EndgameArchetype.randomSquare(
                    distinctFrom: occupied,
                    notEnPrise: kingEnemy,
                    defendedBy: kingOwn
                ) else { return false }
                EndgameArchetype.place(type, color, at: sq, in: &pos)
                occupied.append(sq)
            }
        }
        // Pawns: ranks 1..6 only (rank 0 is impossible, rank 7 is the
        // promotion rank). For white pawns we also reject placements that
        // attack the black king — those would mean it's white to move
        // with black in check (an illegal previous-move state).
        for _ in 0..<counts.pawns {
            var placed = false
            for _ in 0..<50 {
                guard let sq = EndgameArchetype.randomSquare(
                    distinctFrom: occupied,
                    rankRange: 1...6
                ) else { return false }
                if color == .white {
                    let attacks = EndgameArchetype.pawnAttacks(from: sq, color: .white)
                    if attacks.contains(kingEnemy) { continue }
                }
                EndgameArchetype.place(.pawn, color, at: sq, in: &pos)
                occupied.append(sq)
                placed = true
                break
            }
            if !placed { return false }
        }
        return true
    }
}
