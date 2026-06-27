import Foundation

// MARK: - UCI `info` / `bestmove` payload

/// `Sendable` struct mirroring a single UCI `info` line. Named for
/// Stockfish because that's the engine that emits these, but the
/// shape is generic to the UCI protocol; nothing here depends on
/// Stockfish-specific behaviour.
public nonisolated struct UCIInfo: Sendable {
    public var depth: Int = 0
    public var score: Score = .cp(0)
    public var pv: [String] = []
    public var multiPV: Int = 1

    public init(depth: Int = 0, score: Score = .cp(0), pv: [String] = [], multiPV: Int = 1) {
        self.depth = depth
        self.score = score
        self.pv = pv
        self.multiPV = multiPV
    }

    public enum Score: Sendable {
        case cp(Int)
        case mate(Int)

        public var centipawns: Int {
            switch self {
            case .cp(let cp): cp
            case .mate(let m): m > 0 ? 100_000 : -100_000
            }
        }

        public var displayText: String {
            switch self {
            case .cp(let cp):
                let value = Double(cp) / 100.0
                return String(format: "%+.1f", value)
            case .mate(let m):
                return m > 0 ? "M\(m)" : "-M\(abs(m))"
            }
        }

        public var winProbability: Double {
            switch self {
            case .cp(let cp):
                return 1.0 / (1.0 + exp(-0.00368208 * Double(cp)))
            case .mate(let m):
                return m > 0 ? 1.0 : 0.0
            }
        }

        public var whiteWinProbability: Double { winProbability }

        public var negated: Score {
            switch self {
            case .cp(let cp): .cp(-cp)
            case .mate(let m): .mate(-m)
            }
        }
    }
}

// MARK: - Output parsing
//
// Parses Stockfish-specific output formats — `info ...` and
// `bestmove ...` lines. Pure logic with no engine dep; lives here
// instead of inside `StockfishEngine.swift` so the perf harness
// (and any future non-Stockfish consumer) can use it without
// pulling in the C++ bridge.

public nonisolated enum UCIOutputParser {
    public static func parseInfo(_ line: String) -> UCIInfo? {
        guard line.hasPrefix("info "), line.contains(" pv ") else { return nil }
        // Bounded scores (`lowerbound`/`upperbound`) are partial results from an
        // unresolved aspiration window — the true eval is only known to be
        // above/below the printed number. Don't let them drive the eval bar /
        // arrows; the resolved (unbounded) line for that depth follows shortly.
        // (eval-bar fix 2026-06-23)
        if line.contains(" lowerbound") || line.contains(" upperbound") { return nil }
        var info = UCIInfo()
        let tokens = line.split(separator: " ").map(String.init)

        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case "depth":
                i += 1
                if i < tokens.count {
                    info.depth = parsedInt(tokens[i], fallback: 0)
                }
            case "multipv":
                i += 1
                if i < tokens.count {
                    info.multiPV = parsedInt(tokens[i], fallback: 1)
                }
            case "score":
                i += 1
                if i < tokens.count {
                    if tokens[i] == "cp" {
                        i += 1
                        if i < tokens.count {
                            info.score = .cp(parsedInt(tokens[i], fallback: 0))
                        }
                    } else if tokens[i] == "mate" {
                        i += 1
                        if i < tokens.count {
                            info.score = .mate(parsedInt(tokens[i], fallback: 0))
                        }
                    }
                }
            case "pv":
                info.pv = Array(tokens[(i + 1)...])
                i = tokens.count
            default: break
            }
            i += 1
        }
        return info
    }

    public static func parseBestMove(_ line: String) -> String? {
        guard line.hasPrefix("bestmove ") else { return nil }
        let parts = line.split(separator: " ")
        return parts.count >= 2 ? String(parts[1]) : nil
    }

    /// Falls back to a default when the token isn't a valid integer, so a
    /// malformed engine line evaluates as the fallback rather than aborting.
    /// (The app's os.Logger diagnostic was dropped here — logging is app-side.)
    private static func parsedInt(_ token: String, fallback: Int) -> Int {
        Int(token) ?? fallback
    }
}
