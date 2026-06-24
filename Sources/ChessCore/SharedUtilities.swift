import Foundation

// Small shared helpers extracted from logic that was reimplemented in
// several places. (dedup audit 2026-06-16)

/// Whole-percent formatting shared by the drill/stats readouts. Was
/// reimplemented byte-identically as `formatPercent`/`percent`.
public nonisolated enum PercentFormat {
    /// "73%" from a 0…1 fraction; "—" for a non-finite value (e.g. 0/0).
    public static func whole(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }
}

public extension Array {
    /// Trim to the most-recent `max` elements, dropping the oldest. No-op
    /// when already within budget. Was inlined as
    /// `if count > Max { removeFirst(count - Max) }` in the drill stat
    /// stores to bound their CloudKit-synced blobs.
    nonisolated mutating func capLast(_ max: Int) {
        if count > max { removeFirst(count - max) }
    }
}

public extension Position {
    /// Whether a FEN's side-to-move is White. Mirrors the parse the stats /
    /// review snapshot builders did inline (`split[1] == "w"`), defaulting
    /// to true for a present-but-malformed FEN so callers keep the standard
    /// white-to-move assumption.
    nonisolated static func fenStartsWithWhite(_ fen: String) -> Bool {
        let parts = fen.split(separator: " ")
        guard parts.count >= 2 else { return true }
        return parts[1] == "w"
    }
}

/// Decode the annotation-evals blob — a JSON array of centipawn evals
/// (White-oriented). Returns [] for missing / malformed input so callers
/// can size-check against a parallel array. Was reimplemented
/// byte-identically in AccuracyAggregator, TacticsExtractor (×2), and
/// SessionContentView.restoreAnnotations. (dedup 2026-06-17)
public nonisolated enum EvalJSON {
    public static func decode(_ json: String) -> [Double] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let evals = try? JSONDecoder().decode([Double].self, from: data)
        else { return [] }
        return evals
    }

    public static func decodeOptional(_ json: String) -> [Double?] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let evals = try? JSONDecoder().decode([Double?].self, from: data)
        else { return [] }
        return evals
    }
}

public extension PieceColor {
    /// The side to move at 0-based ply index `i`, given the game's
    /// starting side. Collapses the `((i % 2 == 0) == startIsWhite) ?
    /// .white : .black` parity ternary the eval/ply loops repeated in the
    /// stats / tactics / endgame extractors. (dedup 2026-06-17)
    nonisolated static func mover(ply i: Int, startIsWhite: Bool) -> PieceColor {
        ((i % 2 == 0) == startIsWhite) ? .white : .black
    }
}

public extension TimeInterval {
    /// Chess-clock display: "m:ss"; "m:ss.t" (tenths under 10s, when
    /// `showTenths`); or "h:mm:ss" (when `showHours` and the time has
    /// whole hours). Collapses the four hand-rolled clock formatters
    /// (ChessClock / OTBClockView / ReplayClockView / the landscape clock)
    /// that differed only in the showHours / showTenths flags. With
    /// `showHours == false` the minutes field is uncapped (e.g. "90:00").
    /// (dedup 2026-06-17)
    func clockString(showHours: Bool, showTenths: Bool) -> String {
        let clamped = max(0, self)
        let total = Int(clamped)
        if showHours, total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        let minutes = showHours ? (total % 3600) / 60 : total / 60
        let seconds = total % 60
        if showTenths, clamped < 10 {
            return String(format: "%d:%02d.%d", minutes, seconds, Int((clamped - Double(total)) * 10))
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

public extension PieceType {
    /// "K+Q+R+P" / "K+2N+P" style material summary from a piece-count map —
    /// king first, then Q/R/B/N/P, collapsing multiples ("2N"). Was
    /// reimplemented in EndgameArchetype.summary and
    /// PersonalEndgameExtractor.materialString.
    nonisolated static func materialSummary(_ counts: [PieceType: Int]) -> String {
        var parts = ["K"]
        let order: [(PieceType, String)] = [
            (.queen, "Q"), (.rook, "R"), (.bishop, "B"), (.knight, "N"), (.pawn, "P")
        ]
        for (type, letter) in order {
            let n = counts[type] ?? 0
            guard n > 0 else { continue }
            parts.append(n == 1 ? letter : "\(n)\(letter)")
        }
        return parts.joined(separator: "+")
    }
}
