import Foundation

// The foundational chess model — the keystone of the ChessCore carve.
//
// This file holds ONLY the portable value types and their chess/PGN/FEN logic.
// The iOS presentation that was woven into these types in the app's
// `ChessModel.swift` stays app-side and will be reattached as extensions when
// the app is wired to ChessCore:
//   • PieceSet / BoardTheme (SwiftUI colors + asset-catalog names)
//   • Piece.symbol / Piece.assetName (display glyphs + iOS asset names)
//   • MoveAnnotation.displayName / .symbolName / .displayGlyph / .color
//   • MoveQuality.displayName / .sfSymbol / .color
//   • GameState.displayText (localizable UI text)
//   • MoveNode (@Observable; also depends on MoveGenerator — lands with tranche 3)
// The Android app supplies its own (Compose) presentation over these same types.

public nonisolated enum PieceColor: Equatable, Hashable, Codable, Sendable {
    case white, black

    public var opposite: PieceColor {
        self == .white ? .black : .white
    }

    /// Stable "white"/"black" string used as a persisted/CloudKit key
    /// (Repertoire.color, RepertoireMove colour predicates, stats maps).
    /// Centralizes the on-disk contract that was inlined as
    /// `color == .white ? "white" : "black"` at ~20 sites. NOTE: SwiftData
    /// `#Predicate` bodies must keep the bare "white"/"black" literals —
    /// they can't call this. (dedup audit 2026-06-16)
    public var persistenceKey: String { self == .white ? "white" : "black" }

    /// Compact "w"/"b" key for terser maps (stats accumulators, cache keys).
    public var shortKey: String { self == .white ? "w" : "b" }

    public init?(persistenceKey: String) {
        switch persistenceKey {
        case "white": self = .white
        case "black": self = .black
        default: return nil
        }
    }

    /// Which side `username` played, by normalized case-insensitive match
    /// against exactly one player name. Empty, absent, and ambiguous matches
    /// return nil; assigning White merely because both names happen to match
    /// would turn uncertain account metadata into durable derived results.
    public static func ofUser(
        white: String,
        black: String,
        username: String
    ) -> PieceColor? {
        let user = normalizedPlayerIdentity(username)
        guard !user.isEmpty else { return nil }
        let matchesWhite = normalizedPlayerIdentity(white) == user
        let matchesBlack = normalizedPlayerIdentity(black) == user
        switch (matchesWhite, matchesBlack) {
        case (true, false): return .white
        case (false, true): return .black
        case (false, false), (true, true): return nil
        }
    }

    private static func normalizedPlayerIdentity(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}

public nonisolated enum PieceType: Equatable, Hashable, Codable, Sendable {
    case king, queen, rook, bishop, knight, pawn
}

public nonisolated struct Piece: Equatable, Hashable, Codable, Sendable {
    public let type: PieceType
    public let color: PieceColor

    public init(type: PieceType, color: PieceColor) {
        self.type = type
        self.color = color
    }

    public var fenChar: String {
        let ch: String
        switch type {
        case .king: ch = "k"
        case .queen: ch = "q"
        case .rook: ch = "r"
        case .bishop: ch = "b"
        case .knight: ch = "n"
        case .pawn: ch = "p"
        }
        return color == .white ? ch.uppercased() : ch
    }
}

public nonisolated struct Square: Hashable, Equatable, Codable, Sendable {
    public let file: Int
    public let rank: Int

    public var isValid: Bool {
        (0..<8).contains(file) && (0..<8).contains(rank)
    }

    public var fileChar: Character {
        Character(UnicodeScalar(97 + file)!)
    }

    public var algebraic: String {
        "\(fileChar)\(rank + 1)"
    }

    public var index: Int { rank * 8 + file }

    public static func fromIndex(_ index: Int) -> Square {
        Square(file: index % 8, rank: index / 8)
    }

    public init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    public init?(algebraic: String) {
        guard algebraic.count == 2,
              let fileChar = algebraic.first,
              let rankChar = algebraic.last,
              let f = fileChar.asciiValue.map({ Int($0) - 97 }),
              let r = rankChar.wholeNumberValue.map({ $0 - 1 }),
              (0..<8).contains(f), (0..<8).contains(r)
        else { return nil }
        self.file = f
        self.rank = r
    }
}

public nonisolated struct CastlingRights: Equatable, Hashable, Codable, Sendable {
    public var whiteKingside = true
    public var whiteQueenside = true
    public var blackKingside = true
    public var blackQueenside = true

    public init(
        whiteKingside: Bool = true,
        whiteQueenside: Bool = true,
        blackKingside: Bool = true,
        blackQueenside: Bool = true
    ) {
        self.whiteKingside = whiteKingside
        self.whiteQueenside = whiteQueenside
        self.blackKingside = blackKingside
        self.blackQueenside = blackQueenside
    }

    public static let none = CastlingRights(
        whiteKingside: false,
        whiteQueenside: false,
        blackKingside: false,
        blackQueenside: false
    )
}

public nonisolated struct Move: Equatable, Hashable, Sendable {
    public let from: Square
    public let to: Square
    public let piece: PieceType
    public let capturedPiece: PieceType?
    public let promotion: PieceType?
    public let isEnPassant: Bool
    public let isCastling: Bool

    public init(
        from: Square,
        to: Square,
        piece: PieceType,
        capturedPiece: PieceType? = nil,
        promotion: PieceType? = nil,
        isEnPassant: Bool = false,
        isCastling: Bool = false
    ) {
        self.from = from
        self.to = to
        self.piece = piece
        self.capturedPiece = capturedPiece
        self.promotion = promotion
        self.isEnPassant = isEnPassant
        self.isCastling = isCastling
    }

    public var uci: String {
        var s = from.algebraic + to.algebraic
        if let promo = promotion {
            switch promo {
            case .queen: s += "q"
            case .rook: s += "r"
            case .bishop: s += "b"
            case .knight: s += "n"
            default: break
            }
        }
        return s
    }
}

public nonisolated struct MoveRecord: Sendable {
    public let move: Move
    public let notation: String
    public let positionBefore: Position

    public init(move: Move, notation: String, positionBefore: Position) {
        self.move = move
        self.notation = notation
        self.positionBefore = positionBefore
    }
}

/// Move annotation symbols (NAG-ish). Only the chess/PGN logic lives here; the
/// display name, SF Symbol, glyph, and tint are app-side presentation.
public nonisolated enum MoveAnnotation: String, Equatable, Hashable, Sendable, CaseIterable {
    case brilliant = "!!"
    case great = "great"
    case best = "best"
    case excellent = "excellent"
    case good = "!"
    case interesting = "!?"
    case dubious = "?!"
    case miss = "miss"
    case mistake = "?"
    case blunder = "??"

    public var pgnSuffix: String? {
        switch self {
        case .brilliant, .good, .interesting, .dubious, .mistake, .blunder: rawValue
        case .great, .best, .excellent, .miss: nil
        }
    }

    public static func from(nag: Int) -> MoveAnnotation? {
        switch nag {
        case 1: .good
        case 2: .mistake
        case 3: .brilliant
        case 4: .blunder
        case 5: .interesting
        case 6: .dubious
        default: nil
        }
    }

    public static func extract(from san: String) -> (cleaned: String, annotation: MoveAnnotation?) {
        for a in [MoveAnnotation.brilliant, .blunder, .interesting, .dubious] {
            if san.hasSuffix(a.rawValue) {
                return (String(san.dropLast(a.rawValue.count)), a)
            }
        }
        for a in [MoveAnnotation.good, .mistake] {
            if san.hasSuffix(a.rawValue) {
                return (String(san.dropLast(a.rawValue.count)), a)
            }
        }
        return (san, nil)
    }
}

/// Engine move-quality classification. The enum (logic) lives here; its
/// display name, SF Symbol, and tint are app-side presentation.
public nonisolated enum MoveQuality: String, CaseIterable, Sendable {
    case best, excellent, good, inaccuracy, mistake, blunder
}

public nonisolated enum GameState: Equatable, Sendable {
    case playing, check, checkmate, stalemate, draw, insufficientMaterial, repetition

    public var isGameOver: Bool {
        switch self {
        case .checkmate, .stalemate, .draw, .insufficientMaterial, .repetition: true
        case .playing, .check: false
        }
    }
}

public nonisolated struct Position: Equatable, Sendable {
    public var board: [Piece?]
    public var activeColor: PieceColor
    public var castlingRights: CastlingRights
    public var enPassantTarget: Square?
    public var halfmoveClock: Int
    public var fullmoveNumber: Int
    public var whiteKingSquare = Square(file: 4, rank: 0)
    public var blackKingSquare = Square(file: 4, rank: 7)

    public init() {
        board = Array(repeating: nil, count: 64)
        activeColor = .white
        castlingRights = CastlingRights()
        enPassantTarget = nil
        halfmoveClock = 0
        fullmoveNumber = 1
    }

    public subscript(square: Square) -> Piece? {
        get {
            guard square.isValid else { return nil }
            return board[square.index]
        }
        set {
            guard square.isValid else { return }
            board[square.index] = newValue
        }
    }

    public var fen: String {
        var result = ""
        result.reserveCapacity(80)

        for rank in stride(from: 7, through: 0, by: -1) {
            if rank < 7 { result += "/" }
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { result += "\(empty)"; empty = 0 }
                    result += piece.fenChar
                } else {
                    empty += 1
                }
            }
            if empty > 0 { result += "\(empty)" }
        }

        result += " "
        result += activeColor == .white ? "w" : "b"
        result += " "

        var hasCastling = false
        if castlingRights.whiteKingside { result += "K"; hasCastling = true }
        if castlingRights.whiteQueenside { result += "Q"; hasCastling = true }
        if castlingRights.blackKingside { result += "k"; hasCastling = true }
        if castlingRights.blackQueenside { result += "q"; hasCastling = true }
        if !hasCastling { result += "-" }

        result += " "
        result += enPassantTarget?.algebraic ?? "-"
        result += " \(halfmoveClock) \(fullmoveNumber)"

        return result
    }

    public var positionKey: String {
        return fen.split(separator: " ").prefix(4).joined(separator: " ")
    }

    /// Position identity for the threefold-repetition rule.
    ///
    /// FEN records an en-passant target after every double pawn push, even when
    /// no legal en-passant capture exists. Such a target does *not* distinguish
    /// positions for repetition: the legal moves available to both players are
    /// unchanged. ``positionKey`` deliberately preserves raw FEN metadata for
    /// persistence/opening-book callers; this key removes only a non-actionable
    /// en-passant target and is the key game-history code should use.
    public var repetitionKey: String {
        guard enPassantTarget != nil else { return positionKey }

        var normalized = self
        if capturableEnPassantTarget == nil
            || !MoveGenerator.legalMoves(for: self).contains(where: \.isEnPassant) {
            normalized.enPassantTarget = nil
        }
        return normalized.positionKey
    }

    public init?(fen: String) {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: false)
        // Accept either a complete six-field FEN or the four-field position
        // key used by opening/repertoire storage. A five-field or overlong
        // value is neither representation and previously produced a silently
        // defaulted clock.
        guard parts.count == 4 || parts.count == 6 else { return nil }

        self.init()

        let ranks = parts[0].split(separator: "/")
        guard ranks.count == 8 else { return nil }

        for (rankIndex, rankStr) in ranks.enumerated() {
            let rank = 7 - rankIndex
            var file = 0
            for ch in rankStr {
                if let ascii = ch.asciiValue, (49...56).contains(ascii) {
                    file += Int(ascii - 48)
                    guard file <= 8 else { return nil }
                } else {
                    let color: PieceColor = ch.isUppercase ? .white : .black
                    let pieceType: PieceType?
                    switch ch.lowercased() {
                    case "k": pieceType = .king
                    case "q": pieceType = .queen
                    case "r": pieceType = .rook
                    case "b": pieceType = .bishop
                    case "n": pieceType = .knight
                    case "p": pieceType = .pawn
                    default: pieceType = nil
                    }
                    guard let type = pieceType, file < 8 else { return nil }
                    self[Square(file: file, rank: rank)] = Piece(type: type, color: color)
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }

        switch parts[1] {
        case "w": activeColor = .white
        case "b": activeColor = .black
        default: return nil
        }

        let castling = String(parts[2])
        if castling != "-" {
            let rights = Set(castling)
            guard !castling.isEmpty,
                  rights.isSubset(of: Set("KQkq")),
                  rights.count == castling.count
            else { return nil }
        }
        castlingRights = CastlingRights(
            whiteKingside: castling.contains("K"),
            whiteQueenside: castling.contains("Q"),
            blackKingside: castling.contains("k"),
            blackQueenside: castling.contains("q")
        )

        if parts[3] != "-" {
            guard let target = Square(algebraic: String(parts[3])),
                  target.rank == (activeColor == .white ? 5 : 2)
            else { return nil }
            enPassantTarget = target
        }

        if parts.count == 6 {
            guard let hmc = Int(parts[4]), hmc >= 0,
                  let fmn = Int(parts[5]), fmn >= 1
            else { return nil }
            halfmoveClock = hmc
            fullmoveNumber = fmn
        }

        for i in 0..<64 {
            if let piece = board[i], piece.type == .king {
                let sq = Square.fromIndex(i)
                if piece.color == .white { whiteKingSquare = sq }
                else { blackKingSquare = sq }
            }
        }
    }

    public static func initial() -> Position {
        var pos = Position()

        for file in 0..<8 {
            pos[Square(file: file, rank: 1)] = Piece(type: .pawn, color: .white)
            pos[Square(file: file, rank: 6)] = Piece(type: .pawn, color: .black)
        }

        let backRank: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for (file, type) in backRank.enumerated() {
            pos[Square(file: file, rank: 0)] = Piece(type: type, color: .white)
            pos[Square(file: file, rank: 7)] = Piece(type: type, color: .black)
        }

        return pos
    }

    /// FEN with metadata fields sanitised so Stockfish's strict parser
    /// doesn't `assert(is_ok(s))` and abort the whole process on input it
    /// considers inconsistent. We zero out:
    ///   - Castling rights that don't match the actual placement (king on
    ///     its home square AND the matching rook on a1/h1/a8/h8). Stockfish
    ///     walks the board looking for the rook each side is supposedly
    ///     able to castle with — if it isn't there, the search index runs
    ///     off the end of the board and Stockfish aborts.
    ///   - En-passant target that doesn't have the pawn that would have
    ///     just moved sitting in the right square. Stockfish also asserts
    ///     on lone-pawn-less en passant.
    ///
    /// Use this anywhere a FEN crosses the Swift → Stockfish boundary,
    /// instead of the raw `fen` accessor.
    public var stockfishSafeFEN: String {
        var sanitized = self
        sanitized.castlingRights = sanitizedCastlingRights
        sanitized.enPassantTarget = sanitizedEnPassantTarget
        return sanitized.fen
    }

    private var sanitizedCastlingRights: CastlingRights {
        let whiteKing = Square(file: 4, rank: 0)
        let blackKing = Square(file: 4, rank: 7)
        let whiteKingOnHome = self[whiteKing] == Piece(type: .king, color: .white)
        let blackKingOnHome = self[blackKing] == Piece(type: .king, color: .black)

        func rookOn(_ file: Int, _ rank: Int, color: PieceColor) -> Bool {
            self[Square(file: file, rank: rank)] == Piece(type: .rook, color: color)
        }

        return CastlingRights(
            whiteKingside:  castlingRights.whiteKingside  && whiteKingOnHome && rookOn(7, 0, color: .white),
            whiteQueenside: castlingRights.whiteQueenside && whiteKingOnHome && rookOn(0, 0, color: .white),
            blackKingside:  castlingRights.blackKingside  && blackKingOnHome && rookOn(7, 7, color: .black),
            blackQueenside: castlingRights.blackQueenside && blackKingOnHome && rookOn(0, 7, color: .black)
        )
    }

    private var sanitizedEnPassantTarget: Square? {
        guard let target = enPassantTarget else { return nil }
        // After white's double pawn push, target is on rank 3 (0-indexed
        // 2) and the pawn that moved is on rank 4 (0-indexed 3). The
        // reverse for black. Anything else is structurally invalid.
        let expectedPawnRank: Int
        let pawnColor: PieceColor
        switch target.rank {
        case 2: expectedPawnRank = 3; pawnColor = .white
        case 5: expectedPawnRank = 4; pawnColor = .black
        default: return nil
        }
        let pawnSquare = Square(file: target.file, rank: expectedPawnRank)
        guard self[pawnSquare] == Piece(type: .pawn, color: pawnColor) else { return nil }
        return target
    }

    /// The en-passant target only when a capture is genuinely available —
    /// a pawn of the side to move sits beside the pawn that just
    /// double-pushed. This is the X-FEN / Polyglot "real en passant" rule.
    /// Raw FEN records an EP square after *every* double push even when no
    /// pawn can take it; that phantom target makes an otherwise-identical
    /// position reached by a transposing double push (e.g. 1.d4 e6 2.c4 d5)
    /// miss the opening entry that the canonical order (1.d4 d5 2.c4 e6 —
    /// Queen's Gambit Declined, keyed with no EP) is stored under. Used by
    /// the opening-book lookup's transposition fallback.
    /// (opening transposition fix 2026-06-16)
    public var capturableEnPassantTarget: Square? {
        guard let target = enPassantTarget else { return nil }
        // target rank 2 (3rd rank): White double-pushed, Black to capture.
        // target rank 5 (6th rank): Black double-pushed, White to capture.
        let capturingRank: Int
        let capturingColor: PieceColor
        switch target.rank {
        case 2: capturingRank = 3; capturingColor = .black
        case 5: capturingRank = 4; capturingColor = .white
        default: return nil
        }
        guard activeColor == capturingColor else { return nil }
        for df in [-1, 1] {
            let file = target.file + df
            guard (0..<8).contains(file) else { continue }
            if self[Square(file: file, rank: capturingRank)] == Piece(type: .pawn, color: capturingColor) {
                return target
            }
        }
        return nil
    }

    public var hasInsufficientMaterial: Bool {
        var whiteKnights = 0, whiteBishops = 0
        var blackKnights = 0, blackBishops = 0
        var whiteBishopOnLight = false
        var blackBishopOnLight = false

        for i in 0..<64 {
            guard let piece = board[i] else { continue }
            switch piece.type {
            case .pawn, .rook, .queen:
                return false
            case .knight:
                if piece.color == .white { whiteKnights += 1 } else { blackKnights += 1 }
            case .bishop:
                let sq = Square.fromIndex(i)
                let isLight = (sq.file + sq.rank) % 2 == 1
                if piece.color == .white {
                    whiteBishops += 1
                    if isLight { whiteBishopOnLight = true }
                } else {
                    blackBishops += 1
                    if isLight { blackBishopOnLight = true }
                }
            case .king:
                break
            }
        }

        let whiteMinors = whiteKnights + whiteBishops
        let blackMinors = blackKnights + blackBishops

        // K vs K
        if whiteMinors == 0 && blackMinors == 0 { return true }
        // K+minor vs K
        if whiteMinors == 0 && blackMinors == 1 { return true }
        if whiteMinors == 1 && blackMinors == 0 { return true }
        // K+B vs K+B on same color
        if whiteBishops == 1 && blackBishops == 1 && whiteKnights == 0 && blackKnights == 0 {
            let whiteOnLight = whiteBishopOnLight
            let blackOnLight = blackBishopOnLight
            if whiteOnLight == blackOnLight { return true }
        }
        return false
    }
}
