import Foundation
import ChessCore

/// Portable, `Sendable` snapshot of a stored game — the DTO mirror of the app's
/// SwiftData `@Model StoredGame`. PGN tokenization + Elo parsing happen in the
/// `PGNGame` constructor, so callers building a batch on a detached task do the
/// heavy work off-main; the app then maps each DTO onto a `@Model` row (or, on
/// Android, onto a Room row) with cheap scalar assignments.
///
/// The app's `StoredGame` keeps the same fields and delegates its metadata
/// derivations to the static helpers here, so the parsing contract lives once.
public struct PreparedGameData: Sendable, Codable, Equatable {
    public let orderIndex: Int
    public let white: String
    public let black: String
    public let date: String
    public let event: String
    public let result: String
    public let opening: String
    public let moveText: String
    public let tagsJSON: String
    public let gameID: String
    /// Pre-computed cache fields propagated to the persistence row at insert
    /// time so the first library render after a bulk import doesn't pay per-row
    /// PGN tokenization + tag-JSON parse cost. The memberwise constructor
    /// accepts sentinels (`-1`) when the caller doesn't know yet.
    public let cachedMoveCount: Int
    public let cachedWhiteElo: Int
    public let cachedBlackElo: Int
    /// `0` for fresh imports (raw PGN ships no annotation evals).
    public let cachedIsAnnotated: Int

    public init(from pgnGame: PGNGame, orderIndex: Int) {
        self.orderIndex = orderIndex
        self.white = pgnGame.white
        self.black = pgnGame.black
        self.date = pgnGame.date
        self.event = pgnGame.event
        self.result = pgnGame.resultText
        self.opening = pgnGame.opening
        self.moveText = PGNExporter.tokenText(from: pgnGame)
        self.tagsJSON = GameTagCodec.encode(pgnGame.tags)
        // PGN placeholder values ("?", "-", whitespace) read as "absent", not
        // as a stable identifier — treating `[Site "?"]` as a real gameID would
        // collapse unrelated games under the dedup.
        self.gameID = Self.normalizedGameID(
            pgnGame.tags["Link"] ?? pgnGame.tags["Site"] ?? ""
        )
        self.cachedMoveCount = (pgnGame.moves.count + 1) / 2
        self.cachedWhiteElo = Self.parseSanitisedElo(pgnGame.tags["WhiteElo"] ?? "") ?? 0
        self.cachedBlackElo = Self.parseSanitisedElo(pgnGame.tags["BlackElo"] ?? "") ?? 0
        self.cachedIsAnnotated = 0
    }

    public init(
        orderIndex: Int,
        white: String,
        black: String,
        date: String,
        event: String,
        result: String,
        opening: String,
        moveText: String,
        tagsJSON: String,
        gameID: String,
        cachedMoveCount: Int = -1,
        cachedWhiteElo: Int = -1,
        cachedBlackElo: Int = -1,
        cachedIsAnnotated: Int = -1
    ) {
        self.orderIndex = orderIndex
        self.white = white
        self.black = black
        self.date = date
        self.event = event
        self.result = result
        self.opening = opening
        self.moveText = moveText
        self.tagsJSON = tagsJSON
        self.gameID = gameID
        self.cachedMoveCount = cachedMoveCount
        self.cachedWhiteElo = cachedWhiteElo
        self.cachedBlackElo = cachedBlackElo
        self.cachedIsAnnotated = cachedIsAnnotated
    }

    // MARK: - Shared game-metadata helpers
    //
    // The portable parsing contract for a stored game. The app's @Model
    // StoredGame delegates to these so the rules live once (and can't drift
    // between the iOS and Android persistence shells).

    /// Treat PGN placeholder values as missing identifiers.
    public static func normalizedGameID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "?" || trimmed == "-" { return "" }
        return trimmed
    }

    /// Empty / "?" / non-positive Elo strings all collapse to nil.
    public static func parseSanitisedElo(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "?", let elo = Int(trimmed), elo > 0 else { return nil }
        return elo
    }

    /// Annotation detection: non-empty eval JSON, or the literal "; best " tag
    /// in the move text (`.literal` to skip the Unicode/locale fold).
    public static func computeIsAnnotated(evalsJSON: String, moveText: String) -> Bool {
        if !evalsJSON.isEmpty { return true }
        return moveText.range(of: "; best ", options: .literal) != nil
    }

    /// Reconstruct a `PGNGame` from the persisted move text + encoded tags.
    public static func toPGNGame(moveText: String, tagsJSON: String, result: String?) -> PGNGame {
        var game = PGNGame()
        game.tags = GameTagCodec.decodeOrdered(tagsJSON)
        let tokens = PGNParser.tokenize(moveText)
        game.moveTokens = tokens
        game.moves = PGNParser.flatMoves(from: tokens)
        game.result = result
        return game
    }
}
