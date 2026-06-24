import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


public struct ExplorerResult: Sendable {
    public let white: Int
    public let draws: Int
    public let black: Int
    public let moves: [ExplorerMove]

    public var totalGames: Int { white + draws + black }
}

public struct ExplorerMove: Sendable, Identifiable {
    public var id: String { san }
    public let san: String
    public let white: Int
    public let draws: Int
    public let black: Int
    public let averageRating: Int?

    public var totalGames: Int { white + draws + black }
}

public enum ExplorerDatabase: String, CaseIterable, Identifiable {
    case lichess = "Lichess"
    case masters = "Masters"

    public var id: String { rawValue }

    public var endpoint: String {
        switch self {
        case .lichess: "https://explorer.lichess.org/lichess"
        case .masters: "https://explorer.lichess.org/masters"
        }
    }
}

public actor LichessExplorer {
    private let session: URLSession
    private var cache: [String: ExplorerResult] = [:]

    public static let shared = LichessExplorer()

    public init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Fianchetto-ChessApp/1.0"]
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    public func explore(fen: String, database: ExplorerDatabase = .lichess, ratings: [Int] = [1600, 1800, 2000, 2200, 2500], token: String? = nil) async throws -> ExplorerResult {
        let cacheKey = "\(database.rawValue):\(fen)"
        if let cached = cache[cacheKey] { return cached }

        let endpoint: String = switch database {
        case .lichess: "https://explorer.lichess.org/lichess"
        case .masters: "https://explorer.lichess.org/masters"
        }
        guard var components = URLComponents(string: endpoint) else {
            throw ChessAPIError.networkError("Invalid URL")
        }
        var queryItems = [URLQueryItem(name: "fen", value: fen)]
        if database == .lichess {
            queryItems.append(URLQueryItem(name: "ratings", value: ratings.map(String.init).joined(separator: ",")))
            queryItems.append(URLQueryItem(name: "speeds", value: "blitz,rapid,classical"))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ChessAPIError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.dataResult(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw ChessAPIError.unauthorized }
            if http.statusCode == 429 { throw ChessAPIError.rateLimited }
            guard (200...299).contains(http.statusCode) else {
                throw ChessAPIError.networkError("HTTP \(http.statusCode)")
            }
        }

        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let json = parsed as? [String: Any] else {
            // Treat malformed JSON as a network error rather than
            // returning an empty result. The empty-result form rendered
            // as "no data for this position" in the UI — masking the
            // real cause when Lichess returns garbage (rare, but happens
            // on edge / proxy errors) and leaving the explorer cache
            // poisoned with the bogus empty for the rest of the
            // session.
            throw ChessAPIError.networkError("Malformed response from Lichess explorer")
        }
        let result = parseResult(json)

        if result.white + result.draws + result.black > 0 {
            cache[cacheKey] = result
        }

        return result
    }

    public func clearCache() {
        cache.removeAll()
    }

    private func parseResult(_ json: [String: Any]) -> ExplorerResult {
        let white = json["white"] as? Int ?? 0
        let draws = json["draws"] as? Int ?? 0
        let black = json["black"] as? Int ?? 0

        let movesJSON = json["moves"] as? [[String: Any]] ?? []
        let moves = movesJSON.compactMap { moveJSON -> ExplorerMove? in
            guard let san = moveJSON["san"] as? String else { return nil }
            return ExplorerMove(
                san: san,
                white: moveJSON["white"] as? Int ?? 0,
                draws: moveJSON["draws"] as? Int ?? 0,
                black: moveJSON["black"] as? Int ?? 0,
                averageRating: moveJSON["averageRating"] as? Int
            )
        }

        return ExplorerResult(white: white, draws: draws, black: black, moves: moves)
    }
}
