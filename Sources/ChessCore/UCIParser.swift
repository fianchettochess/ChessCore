import Foundation

// MARK: - UCI move-string translation
//
// Pure SAN ↔ UCI translation against a Position. Parsing an engine's output
// stream (`info …` and `bestmove …` lines) lives in `UCIOutputParser.swift`;
// everything here is about the move strings themselves and is equally useful
// to PGN, annotation, and command-line consumers.

public enum UCIParser {
    public static func uciToMove(_ uci: String, in position: Position) -> Move? {
        uciToMove(uci, in: MoveGenerator.legalMoves(for: position))
    }

    public static func uciToMove(_ uci: String, in legalMoves: [Move]) -> Move? {
        // Coordinate moves are exactly four characters, or five with a
        // lowercase promotion piece. Prefix parsing would let malformed
        // backup/engine data such as `e2e4junk` silently select a legal move.
        guard uci.count == 4 || uci.count == 5 else { return nil }
        let chars = Array(uci)
        guard let fromFile = fileIndex(chars[0]),
              let fromRank = rankIndex(chars[1]),
              let toFile = fileIndex(chars[2]),
              let toRank = rankIndex(chars[3]) else { return nil }

        let from = Square(file: fromFile, rank: fromRank)
        let to = Square(file: toFile, rank: toRank)

        let promotion: PieceType?
        if uci.count == 5 {
            guard let parsed = promotionType(chars[4]) else { return nil }
            promotion = parsed
        } else {
            promotion = nil
        }

        // Equality is intentional: a promotion may not omit its fifth
        // character, and a non-promotion may not carry a spurious one.
        return legalMoves.first {
            $0.from == from && $0.to == to && $0.promotion == promotion
        }
    }

    public static func uciToSAN(_ uci: String, in position: Position) -> String? {
        let legal = MoveGenerator.legalMoves(for: position)
        guard let move = uciToMove(uci, in: legal) else { return nil }
        return MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: legal)
    }

    public static func sanToUCI(_ san: String, in position: Position) -> String? {
        guard let move = PGNParser.parseMove(san, in: position) else { return nil }
        return move.uci
    }

    public static func convertPVToSAN(_ uciMoves: [String], from position: Position, initialLegalMoves: [Move]? = nil) -> [String] {
        var pos = position
        var sanMoves: [String] = []
        for (i, uci) in uciMoves.enumerated() {
            let legal = (i == 0) ? (initialLegalMoves ?? MoveGenerator.legalMoves(for: pos)) : MoveGenerator.legalMoves(for: pos)
            guard let move = uciToMove(uci, in: legal) else { break }
            sanMoves.append(MoveGenerator.algebraicNotation(for: move, in: pos, legalMoves: legal))
            MoveGenerator.applyMoveUnchecked(&pos, move)
        }
        return sanMoves
    }

    private static func fileIndex(_ c: Character) -> Int? {
        guard c >= "a", c <= "h", let v = c.asciiValue, let a = Character("a").asciiValue else { return nil }
        return Int(v - a)
    }

    private static func rankIndex(_ c: Character) -> Int? {
        guard c >= "1", c <= "8", let v = c.asciiValue, let one = Character("1").asciiValue else { return nil }
        return Int(v - one)
    }

    private static func promotionType(_ c: Character) -> PieceType? {
        switch c {
        case "q": .queen; case "r": .rook; case "b": .bishop; case "n": .knight
        default: nil
        }
    }
}
