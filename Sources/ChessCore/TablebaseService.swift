import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


public struct TablebaseResult: Sendable {
    public enum Category: String, Sendable {
        case win, loss, draw, cursedWin = "cursed-win", blessedLoss = "blessed-loss", unknown

        var displayText: String {
            switch self {
            case .win: "Win"
            case .loss: "Loss"
            case .draw: "Draw"
            case .cursedWin: "Cursed Win"
            case .blessedLoss: "Blessed Loss"
            case .unknown: "Unknown"
            }
        }

        var isDecisive: Bool {
            self == .win || self == .loss || self == .cursedWin || self == .blessedLoss
        }
    }

    public let category: Category
    public let dtm: Int?
    public let dtz: Int?
    public let bestMove: String?
    public let moves: [TablebaseMove]
}

public struct TablebaseMove: Sendable, Identifiable {
    public var id: String { uci }
    public let uci: String
    public let san: String?
    public let category: TablebaseResult.Category
    public let dtm: Int?
    public let dtz: Int?

    /// Verdict of this move from the **moving side's** POV.
    ///
    /// Lichess reports each move's `category` from the *opponent's*
    /// perspective — the side to move *after* the move is played. So
    /// a move with `category: "loss"` means the opponent is losing
    /// after our move, which means our move *keeps the win*. The
    /// EndgameTrainerView filter was historically inverted (filtering
    /// for `.win`, which selects suicide moves) and the drill was
    /// permanently flagging every winning K+Q-vs-K probe as drawn —
    /// burning all three regen attempts before surfacing as
    /// "Tablebase unavailable". This translator is the single source
    /// of truth for the from-our-POV mapping; route every consumer
    /// through it instead of repeating the case mapping inline.
    public enum UserVerdict: Equatable, Sendable {
        /// Move keeps a winning position (opponent now losing).
        case keepsWin
        /// Move converts to a draw (opponent now drawing).
        case draws
        /// Move loses the win (opponent now winning).
        case losesWin
        /// Tablebase didn't classify the resulting position.
        case unknown

        /// Short label suitable for the analysis tablebase popover.
        /// The display matches the user's mental model — a move that
        /// keeps a winning position reads as "Win", not the raw
        /// opponent-POV "Loss" from the API.
        var displayText: String {
            switch self {
            case .keepsWin: "Win"
            case .draws: "Draw"
            case .losesWin: "Loss"
            case .unknown: "Unknown"
            }
        }
    }

    public var userVerdict: UserVerdict {
        switch category {
        case .loss, .blessedLoss: return .keepsWin
        case .draw: return .draws
        case .win, .cursedWin: return .losesWin
        case .unknown: return .unknown
        }
    }
}

public actor TablebaseService {
    private let session: URLSession
    private var cache: [String: TablebaseResult] = [:]

    public static let shared = TablebaseService()

    public init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Fianchetto-ChessApp/1.0"]
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    public static func pieceCount(for position: Position) -> Int {
        position.board.compactMap { $0 }.count
    }

    public func probe(fen: String) async throws -> TablebaseResult {
        if let cached = cache[fen] { return cached }

        guard var components = URLComponents(string: "https://tablebase.lichess.ovh/standard") else {
            throw ChessAPIError.networkError("Invalid URL")
        }
        components.queryItems = [URLQueryItem(name: "fen", value: fen)]

        guard let url = components.url else {
            throw ChessAPIError.networkError("Invalid URL")
        }

        do {
            let (data, response) = try await session.dataResult(for: URLRequest(url: url))
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    // FENs identify game positions and can leak ongoing
                    // tournament games via Console / device log
                    // exports. Mark them `.private` so they're redacted
                    // outside development builds.
                    throw ChessAPIError.rateLimited
                }
                guard (200...299).contains(http.statusCode) else {
                    // 4xx usually means the FEN was rejected — surface that
                    // with the FEN and a snippet of the response body so we
                    // can diagnose without a re-run. FEN + URL stay
                    // private (URL includes the FEN as a query param).
                    let body = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                    throw ChessAPIError.networkError("HTTP \(http.statusCode)")
                }
            }

            let parsed = try JSONSerialization.jsonObject(with: data)
            guard let json = parsed as? [String: Any] else {
                throw ChessAPIError.networkError("Could not parse tablebase response")
            }
            let result = parseResult(json)
            cache[fen] = result
            return result
        } catch let urlError as URLError {
            // FEN stays `.private` here — same reasoning as the
            // rate-limit / 4xx branches above. The URLError branch
            // had been logging `.public` so the FEN could leak into
            // sysdiagnose / Console transcripts that the other
            // branches deliberately avoid. (V1-REVIEW 2026-06-09 §3 low)
            throw urlError
        }
    }

    public func clearCache() {
        cache.removeAll()
    }

    private func parseResult(_ json: [String: Any]) -> TablebaseResult {
        let catStr = json["category"] as? String ?? "unknown"
        let category = TablebaseResult.Category(rawValue: catStr) ?? .unknown
        let dtm = json["dtm"] as? Int
        let dtz = json["dtz"] as? Int
        let bestMove = json["bestmove"] as? String

        let movesJSON = json["moves"] as? [[String: Any]] ?? []
        let moves = movesJSON.compactMap { moveJSON -> TablebaseMove? in
            guard let uci = moveJSON["uci"] as? String else { return nil }
            let mCat = TablebaseResult.Category(rawValue: moveJSON["category"] as? String ?? "unknown") ?? .unknown
            return TablebaseMove(
                uci: uci,
                san: moveJSON["san"] as? String,
                category: mCat,
                dtm: moveJSON["dtm"] as? Int,
                dtz: moveJSON["dtz"] as? Int
            )
        }

        return TablebaseResult(category: category, dtm: dtm, dtz: dtz, bestMove: bestMove, moves: moves)
    }
}
