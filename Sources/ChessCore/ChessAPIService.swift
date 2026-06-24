import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


public enum ChessPlatform: String, CaseIterable, Identifiable {
    case chesscom = "Chess.com"
    case lichess = "Lichess"

    public var id: String { rawValue }
}

/// `nonisolated`: these errors are constructed and thrown from the
/// `@concurrent` fetch methods on the cooperative pool, so neither the
/// cases nor the `LocalizedError` witness may be bound to the project's
/// default MainActor isolation. (main-thread hang fix 2026-06-12)
public nonisolated enum ChessAPIError: LocalizedError {
    case invalidUsername
    case networkError(String)
    case noGamesFound
    case rateLimited
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .invalidUsername: "User not found"
        case .networkError(let msg): "Network error: \(msg)"
        case .noGamesFound: "No games found for this user"
        case .rateLimited: "Rate limited — please wait a moment and try again"
        case .unauthorized: "Authentication required — add your Lichess API token in the explorer settings"
        }
    }
}

/// Fully `nonisolated` service: the entire fetch + parse pipeline must
/// run on the cooperative pool, never the main actor — a Chess.com
/// multi-month sweep parses every archive's PGN and the Lichess export
/// accumulates byte-by-byte, both of which beachball the UI if any part
/// of the pipeline lands on main. Two details are load-bearing here:
///
/// - The fetch methods are `@concurrent`, not merely nonisolated. With
///   the project's Approachable Concurrency settings
///   (`NonisolatedNonsendingByDefault`), a plain `nonisolated async`
///   method runs on the *caller's* actor — called from a MainActor
///   view, the whole download/parse would silently hop back onto the
///   main thread. `@concurrent` pins execution to the pool.
/// - The type is `Sendable` (final, all stored state is immutable
///   `URLSession`s) so MainActor views can hold an instance and pass it
///   into off-main work without warnings (warnings are errors here).
///
/// Progress callbacks are `@MainActor` so call-site `@State` writes
/// stay correct — the service hops to main once per progress TICK
/// (per archive month), not per unit of downloaded work.
/// (main-thread hang fix 2026-06-12)
public nonisolated final class ChessAPIService: Sendable {

    /// Allowed characters for a single path *segment*: `.urlPathAllowed`
    /// minus "/". The stock set treats "/" as a legal path character,
    /// so encoding a username with it left "foo/bar" crossing path-
    /// segment boundaries unencoded — the exact injection the encoding
    /// was added to stop. (V1-REVIEW follow-up 2026-06-10 §3 #20 /
    /// URL-encoding residual)
    private static let pathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()
    private let session: URLSession
    /// Dedicated long-resource session for the Lichess streaming
    /// export. The default `session` caps total transfer at 180 s,
    /// which is reasonable for chess.com's archive-per-month shape
    /// but guarantees failure for the Lichess account export, which
    /// is a single long stream of every game ever played by the
    /// user. The audit (V1-REVIEW §4 #5) flagged the 180 s cap as
    /// the cause of large-account import failures. The streaming
    /// session also opts out of `timeoutIntervalForRequest`
    /// (per-segment idle) because Lichess pushes one game then
    /// pauses while it fetches the next from disk — short idle
    /// gaps shouldn't fault the connection.
    private let streamSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Fianchetto-ChessApp/1.0"
        ]
        // Bound per-request (response start) and total-transfer
        // (whole-archive download) wait times so a stalled chess.com
        // archive endpoint can't leave the import sheet spinning
        // indefinitely. Without `timeoutIntervalForResource`,
        // URLSession only enforces the per-segment idle timer —
        // perfectly slow streams stay open forever.
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)

        let streamConfig = URLSessionConfiguration.default
        streamConfig.httpAdditionalHeaders = [
            "User-Agent": "Fianchetto-ChessApp/1.0"
        ]
        // 2 hours total for the largest accounts; 60 s idle for
        // server-side pauses between games. The user can cancel
        // by dismissing the sheet (the import task is bound to
        // the view's lifecycle).
        streamConfig.timeoutIntervalForRequest = 60
        streamConfig.timeoutIntervalForResource = 7_200
        self.streamSession = URLSession(configuration: streamConfig)
    }

    // MARK: - Chess.com

    /// Result of a Chess.com archive fetch. Carries the games AND a
    /// list of archives that errored during the sweep, so the caller
    /// can decide whether to advance `lastSyncDate` (a clean sweep
    /// should; a partial one should NOT, or the cheap incremental
    /// path will skip those months on every subsequent Update Games
    /// run). The previous return type was `[PGNGame]`, with internal
    /// failures silently swallowed via `continue` — exactly the
    /// surface the 2026-06-09 audit flagged (V1-REVIEW §7) as the
    /// cause of permanently-missing months on long-lived accounts.
    public struct ChessComFetchResult: Sendable {
        let games: [PGNGame]
        let failedArchives: [String]
        var isPartial: Bool { !failedArchives.isEmpty }
    }

    @concurrent
    public func fetchChessComGames(username: String, since: Date? = nil, onProgress: (@MainActor @Sendable (Int, Int) -> Void)? = nil) async throws -> ChessComFetchResult {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { throw ChessAPIError.invalidUsername }

        // Percent-encode the username before interpolating it into
        // the URL path. Chess.com usernames are nominally
        // alphanumeric + underscore + hyphen, but the field comes
        // from user input — a username with a slash, space, or
        // URL-significant character would otherwise quietly cross
        // path boundaries. (V1-REVIEW 2026-06-09 §3 low; segment set
        // per the follow-up — `.urlPathAllowed` doesn't encode "/")
        guard let encodedUser = trimmed.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed),
              let archivesURL = URL(string: "https://api.chess.com/pub/player/\(encodedUser)/games/archives") else {
            throw ChessAPIError.networkError("Invalid URL")
        }
        let (archivesData, archivesResponse) = try await session.dataResult(from: archivesURL)

        if let httpResponse = archivesResponse as? HTTPURLResponse {
            if httpResponse.statusCode == 404 { throw ChessAPIError.invalidUsername }
            if httpResponse.statusCode == 429 { throw ChessAPIError.rateLimited }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ChessAPIError.networkError("HTTP \(httpResponse.statusCode)")
            }
        }

        let archives: [String]
        do {
            let parsed = try JSONSerialization.jsonObject(with: archivesData)
            guard let json = parsed as? [String: Any],
                  let urls = json["archives"] as? [String] else {
                throw ChessAPIError.noGamesFound
            }
            archives = urls
        } catch is ChessAPIError {
            throw ChessAPIError.noGamesFound
        } catch {
            throw ChessAPIError.networkError("Could not parse Chess.com response")
        }

        let filtered: [String]
        if let since {
            let cal = Calendar.current
            let sinceYear = cal.component(.year, from: since)
            let sinceMonth = cal.component(.month, from: since)
            filtered = archives.filter { url in
                let parts = url.split(separator: "/")
                guard parts.count >= 2,
                      let year = Int(parts[parts.count - 2]),
                      let month = Int(parts[parts.count - 1]) else { return true }
                return year > sinceYear || (year == sinceYear && month >= sinceMonth)
            }
        } else {
            filtered = archives
        }

        let allArchives = filtered.reversed()
        let total = allArchives.count
        var allGames: [PGNGame] = []
        var failedArchives: [String] = []

        for (index, archiveURL) in allArchives.enumerated() {
            guard let pgnURL = URL(string: archiveURL + "/pgn") else {
                failedArchives.append(archiveURL)
                continue
            }
            do {
                let (pgnData, pgnResponse) = try await session.dataResult(from: pgnURL)
                if let httpResponse = pgnResponse as? HTTPURLResponse,
                   httpResponse.statusCode == 429 {
                    throw ChessAPIError.rateLimited
                }
                if let pgnText = String(data: pgnData, encoding: .utf8) {
                    let games = PGNParser.parse(pgnText)
                    allGames.append(contentsOf: games)
                }
            } catch let apiError as ChessAPIError {
                // Re-throw the actual API error rather than coercing
                // every flavour ("noGamesFound", "unauthorized", etc.)
                // into `rateLimited`. The old `catch is ChessAPIError`
                // form lost the underlying diagnosis on the way out
                // and left users staring at a "rate limited" toast
                // for a missing-archive or auth problem.
                throw apiError
            } catch {
                // Track the failure rather than silently continuing.
                // The caller (`updateCollection`) inspects
                // `result.isPartial` to decide whether to advance
                // `lastSyncDate` — leaving it unchanged when any
                // archive failed means the next Update Games run
                // re-sweeps the same months instead of skipping
                // them forever. (V1-REVIEW §7)
                failedArchives.append(archiveURL)
            }
            // Explicit main-actor hop, once per archive month — the
            // only part of this method that touches the main thread.
            // (main-thread hang fix 2026-06-12)
            await onProgress?(index + 1, total)
        }

        guard !allGames.isEmpty else { throw ChessAPIError.noGamesFound }
        return ChessComFetchResult(games: allGames, failedArchives: failedArchives)
    }

    // MARK: - Lichess

    @concurrent
    public func fetchLichessGames(username: String, since: Date? = nil, token: String? = nil) async throws -> [PGNGame] {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { throw ChessAPIError.invalidUsername }

        // Percent-encode the username path component — same
        // reasoning as fetchChessComGames above. Lichess usernames
        // are alphanumeric + underscore + hyphen per the docs, but
        // we don't validate that here; encoding is defensive.
        // (V1-REVIEW §3 low; segment set per the follow-up)
        guard let encodedUser = trimmed.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed),
              var components = URLComponents(string: "https://lichess.org/api/games/user/\(encodedUser)") else {
            throw ChessAPIError.networkError("Invalid URL")
        }
        var queryItems = [
            URLQueryItem(name: "opening", value: "true"),
        ]
        if let since {
            let ms = Int64(since.timeIntervalSince1970 * 1000)
            queryItems.append(URLQueryItem(name: "since", value: String(ms)))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw ChessAPIError.networkError("Invalid URL") }
        var request = URLRequest(url: url)
        request.setValue("application/x-chess-pgn", forHTTPHeaderField: "Accept")
        // Bearer-token-authenticated requests get 3× the export
        // rate per Lichess docs; without the token, large accounts
        // are throttled to a crawl. The token is optional — when
        // the user hasn't set one in Settings, we fall back to the
        // anonymous endpoint. (V1-REVIEW §4 #5)
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // `bytes(for:)` reads the response incrementally, but the
        // loop below still accumulates the ENTIRE export into one
        // Data + String before parsing — peak memory is the full
        // payload size, bounded only by whatever limits the request
        // itself imposes (e.g. the `since` filter), not by the
        // streaming read. The real win over `data(for:)` is that a
        // partial read isn't dropped on a mid-stream disconnect —
        // we still parse whatever we got. True incremental NDJSON
        // parsing (per-game decode as lines arrive, constant
        // memory) is deferred.
        // (V1-REVIEW follow-up 2026-06-10 §2, streaming deferred)
        //
        // The per-byte accumulation below runs entirely on the
        // cooperative pool (`@concurrent` method) — zero main-actor
        // jobs regardless of export size. The iteration is kept
        // byte-wise on purpose: `bytes.lines` would change newline
        // fidelity and invalid-UTF-8 handling versus the explicit
        // `String(data:encoding:)` validation below.
        // (main-thread hang fix 2026-06-12)
        // Was `bytes(for:)` streaming (iOS 15 / macOS 12). Switched to the
        // back-deployed `dataResult(for:)` so the service stays on ChessCore's
        // iOS 13 / macOS 10.15 floor and is portable to Android Foundation. The
        // streaming read only avoided dropping a partial body on a mid-stream
        // disconnect; peak memory was the full payload either way (see below).
        let (data, response) = try await streamSession.dataResult(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 { throw ChessAPIError.unauthorized }
            if httpResponse.statusCode == 404 { throw ChessAPIError.invalidUsername }
            if httpResponse.statusCode == 429 { throw ChessAPIError.rateLimited }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ChessAPIError.networkError("HTTP \(httpResponse.statusCode)")
            }
        }

        guard let pgnText = String(data: data, encoding: .utf8), !pgnText.isEmpty else {
            throw ChessAPIError.noGamesFound
        }

        let games = PGNParser.parse(pgnText)
        guard !games.isEmpty else { throw ChessAPIError.noGamesFound }
        return games
    }
}
