import Foundation

// MARK: - UCI `info` / `bestmove` payload

/// A structured snapshot of a single UCI `info` line.
///
/// Centipawn and mate scores are stored separately, while ``score`` provides a
/// unified enum view. Scores are engine-POV (positive = good for the side to
/// move) until normalized to White-POV via
/// ``whitePovCp(_:sideToMoveIsWhite:)`` or
/// ``whitePovMate(_:sideToMoveIsWhite:)``.
public struct UCIInfo: Sendable, Equatable {
    /// Depth completed by the engine for this line.
    public var depth: Int?
    /// MultiPV rank (1 = best move, 2 = second-best, …).
    public var multipv: Int?
    /// Engine-POV centipawns (nil when the score is a forced mate).
    public var scoreCp: Int?
    /// Signed forced-mate distance (engine-POV). Positive = current mover
    /// mates; negative = current mover is mated.
    public var mateIn: Int?
    /// Nodes-per-second search rate reported by the engine.
    public var nps: Int?
    /// Principal variation — a list of UCI move strings (e.g. `"e2e4"`).
    public var pv: [String]

    public init(
        depth: Int? = nil,
        multipv: Int? = nil,
        scoreCp: Int? = nil,
        mateIn: Int? = nil,
        nps: Int? = nil,
        pv: [String] = []
    ) {
        self.depth = depth
        self.multipv = multipv
        self.scoreCp = scoreCp
        self.mateIn = mateIn
        self.nps = nps
        self.pv = pv
    }

    // MARK: - Unified score view

    /// The score as a unified `.cp`/`.mate` enum, or `nil` when this `info`
    /// line did not report a score. Getter derives it from `scoreCp`/`mateIn`;
    /// the setter writes it back to the same storage.
    ///
    /// UCI permits useful scoreless lines such as `info depth 12 pv e2e4`.
    /// Keeping that absence explicit prevents a principal variation from being
    /// mistaken for an equal (`cp 0`) evaluation.
    public var score: Score? {
        get {
            if let m = mateIn { return .mate(m) }
            if let cp = scoreCp { return .cp(cp) }
            return nil
        }
        set {
            switch newValue {
            case .cp(let c)?: scoreCp = c; mateIn = nil
            case .mate(let m)?: mateIn = m; scoreCp = nil
            case nil: scoreCp = nil; mateIn = nil
            }
        }
    }

    /// Convenience spelling of `multipv` that defaults to 1 when absent.
    public var multiPV: Int {
        get { multipv ?? 1 }
        set { multipv = newValue }
    }

    /// Best move from this position, i.e. the first token of the PV.
    public var bestMoveUCI: String? { pv.first }

    // MARK: - Derived score helpers

    /// Engine-POV centipawns treating a forced mate as ±100 000, or `nil`
    /// when the line did not report a score.
    public var centipawns: Int? {
        score?.centipawns
    }

    /// White-POV centipawn value. Flips sign when the side to move is Black.
    public static func whitePovCp(_ cp: Int, sideToMoveIsWhite: Bool) -> Int {
        sideToMoveIsWhite ? cp : -cp
    }

    /// White-POV mate distance. Positive = White mates; negative = Black mates.
    public static func whitePovMate(_ mate: Int, sideToMoveIsWhite: Bool) -> Int {
        sideToMoveIsWhite ? mate : -mate
    }

    /// White-POV centipawns using this line's own score (mate → ±100 000), or
    /// `nil` when the line did not report a score.
    public func whitePovCentipawns(sideToMoveIsWhite: Bool) -> Int? {
        centipawns.map {
            UCIInfo.whitePovCp($0, sideToMoveIsWhite: sideToMoveIsWhite)
        }
    }

    /// Human-readable eval string: `"+1.3"` / `"-0.2"` / `"M5"` / `"-M3"` —
    /// one decimal place for centipawn scores.
    public var displayText: String? { score?.displayText }

    // MARK: - Score

    public enum Score: Sendable, Equatable {
        case cp(Int)
        case mate(Int)

        public var centipawns: Int {
            switch self {
            case .cp(let cp): cp
            case .mate(let m): m > 0 ? 100_000 : -100_000
            }
        }

        /// `"+1.3"` (one decimal) / `"M5"` / `"-M3"`. Integer arithmetic
        /// avoids floating-point rounding differences between platforms.
        public var displayText: String {
            switch self {
            case .cp(let cp):
                let sign = cp < 0 ? "-" : "+"
                let a = abs(cp)
                return "\(sign)\(a / 100).\((a % 100) / 10)"
            case .mate(let m): return m > 0 ? "M\(m)" : "-M\(abs(m))"
            }
        }

        public var negated: Score {
            switch self {
            case .cp(let cp): .cp(-cp)
            case .mate(let m): .mate(-m)
            }
        }
    }

}

// MARK: - UCIOutputParser

/// Pure-logic parser for UCI engine output. Converts `info …` and `bestmove …`
/// lines into `UCIInfo` values. It links against no engine, so a test harness
/// or a log reader can use it with no engine present at all.
///
/// Parsing behavior:
/// - Discards bounded (`lowerbound`/`upperbound`) scores — aspiration-window
///   artefacts whose true eval is only known to be above/below the number.
/// - Does NOT require a `pv` token, so score-only probe lines still parse
///   (one-shot probes and terminal positions — `info depth 0 score mate 0` —
///   depend on this). Lines with NEITHER a score NOR a pv (`currmove`
///   progress ticks) are rejected as noise: they carry nothing to report, and
///   keyed by `multipv ?? 1` they would overwrite pv-bearing rank-1 entries in
///   a per-rank accumulator.
/// - Parses `nps`.
/// - Stops at `string`, `refutation` and `currline`, which UCI defines as
///   running to the end of the line. Their contents are never read as fields.
/// - `parseBestMove` treats `bestmove (none)` as `nil` (terminal position).
public enum UCIOutputParser {

    /// Parse a single engine output line. Returns a `UCIInfo` for `info …`
    /// lines; `nil` for anything else (`bestmove`, `readyok`, blanks, …).
    public static func parseInfo(_ line: String) -> UCIInfo? {
        // Keep tokens as Substrings (they share `line`'s buffer); convert to
        // String only where stored (`pv`). Drops a per-line intermediate [String]
        // array on the engine's highest-frequency output.
        let tokens = line.split(separator: " ")
        guard tokens.first == "info" else { return nil }


        var result = UCIInfo()
        var i = 1
        while i < tokens.count {
            switch tokens[i] {
            case "depth":
                if i + 1 < tokens.count { result.depth = Int(tokens[i + 1]) }
                i += 2
            case "multipv":
                if i + 1 < tokens.count { result.multipv = Int(tokens[i + 1]) }
                i += 2
            case "nps":
                if i + 1 < tokens.count { result.nps = Int(tokens[i + 1]) }
                i += 2
            case "score":
                if i + 2 < tokens.count {
                    let kind = tokens[i + 1]
                    let value = Int(tokens[i + 2])
                    // UCI: `score cp <x> [lowerbound|upperbound]` — the bound
                    // qualifies THIS score and can only follow its value.
                    // Matching it positionally rather than anywhere in the line
                    // is what keeps a pv move or free text from being read as a
                    // bound.
                    if i + 3 < tokens.count,
                       tokens[i + 3] == "lowerbound" || tokens[i + 3] == "upperbound" {
                        // An aspiration-window artefact: the true eval is only
                        // known to be above/below the number, so the line is
                        // discarded rather than reported as a real score.
                        return nil
                    }
                    if kind == "cp" { result.scoreCp = value }
                    else if kind == "mate" { result.mateIn = value }
                }
                i += 3
            case "pv":
                if i + 1 < tokens.count { result.pv = tokens[(i + 1)...].map(String.init) }
                i = tokens.count
            case "string", "refutation", "currline":
                // UCI defines all three as running to end of line: `string` is
                // free text for display ("should be the last command on the
                // line"), and refutation/currline carry move lists. Scanning
                // past them reads free text as engine fields — an engine that
                // logged "info string fallback pv e2e4 is unavailable" yielded
                // a pv of ["e2e4", "is", "unavailable"], and one that logged a
                // score in a string produced a FABRICATED evaluation that the
                // per-rank accumulator would then treat as rank 1. Stop here;
                // the score/pv guard below then rejects the line as noise.
                i = tokens.count
            default:
                i += 1
            }
        }
        // Progress noise (`info depth 20 currmove e2e4 currmovenumber 5`):
        // no score, no pv — nothing any consumer reads, but dangerous to
        // return (defaults to rank 1, overwriting real MultiPV entries).
        guard result.scoreCp != nil || result.mateIn != nil || !result.pv.isEmpty else { return nil }
        return result
    }

    /// A concise alias for ``parseInfo(_:)``.
    public static func parse(_ line: String) -> UCIInfo? { parseInfo(line) }

    /// Extract the move from a `bestmove <uci> [ponder <uci>]` line. Returns
    /// `nil` for any other line, or when the engine reports `bestmove (none)`.
    public static func parseBestMove(_ line: String) -> String? {
        let tokens = line.split(separator: " ")
        guard tokens.first == "bestmove", tokens.count >= 2 else { return nil }
        let move = tokens[1]
        return move == "(none)" ? nil : String(move)
    }

    /// Distil a batch of `UCIInfo` values (e.g. from a MultiPV search) into a
    /// dictionary keyed by MultiPV rank, keeping the highest-depth entry per
    /// rank. A later entry wins when depths are equal, and an entry without a
    /// depth only replaces another depthless entry. Lines without a `multipv`
    /// field default to rank 1.
    public static func bestInfoByRank(_ infos: [UCIInfo]) -> [Int: UCIInfo] {
        var best: [Int: UCIInfo] = [:]
        for info in infos {
            let rank = info.multipv ?? 1
            guard let current = best[rank] else {
                best[rank] = info
                continue
            }

            switch (current.depth, info.depth) {
            case let (currentDepth?, newDepth?) where newDepth < currentDepth:
                continue
            case (_?, nil):
                continue
            default:
                // The new entry is deeper, equally deep, or both entries have
                // no depth. Prefer it so the most recent data wins ties.
                best[rank] = info
            }
        }
        return best
    }
}
