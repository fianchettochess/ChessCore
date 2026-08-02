import Foundation

/// Typed access to the PGN metadata of a loaded game: the Seven Tag Roster
/// player fields, the `TimeControl` tag, and the per-ply `[%clk]` annotations
/// reconstructed into a clock reading at any point in the game.
///
/// These read what PGN defines and return values, not decisions. Whether a
/// rating is worth showing, how a clock is formatted, and whether any of it
/// appears on screen are all the caller's.
extension Game {

    // MARK: - Clocks

    /// Whether the loaded game carries per-ply clock annotations.
    ///
    /// PGN records them as `{[%clk 0:02:58]}` after a move; a game exported
    /// without them has no clock history to reconstruct.
    public var hasClockAnnotations: Bool {
        rootChildren.first?.clockSeconds != nil
    }

    /// Both sides' clock readings at the currently selected node, together
    /// with the side to move.
    ///
    /// Each side's reading is the most recent `[%clk]` value on its own moves
    /// along the path from the root. Before a side has made an annotated move
    /// its reading falls back to `initialClockSeconds`, so a game reads
    /// sensibly from ply 1 rather than starting blank. Both readings are `nil`
    /// when the game has no clock annotations at all.
    public var clockTimes: (white: TimeInterval?, black: TimeInterval?, active: PieceColor) {
        let active = position.activeColor

        guard hasClockAnnotations else {
            return (nil, nil, active)
        }

        if currentNode == nil {
            let initial = initialClockSeconds
            return (initial, initial, .white)
        }

        let path = currentNode?.pathFromRoot() ?? []
        var whiteTime: TimeInterval?
        var blackTime: TimeInterval?
        for node in path {
            if node.moverColor == .white {
                if let clk = node.clockSeconds { whiteTime = clk }
            } else {
                if let clk = node.clockSeconds { blackTime = clk }
            }
        }

        if whiteTime == nil { whiteTime = initialClockSeconds }
        if blackTime == nil { blackTime = initialClockSeconds }

        return (whiteTime, blackTime, active)
    }

    /// Seconds on the clock at the start of the game, from the PGN
    /// `TimeControl` tag.
    ///
    /// `nil` when the tag is absent, unknown (`?`), or declares no time
    /// control (`-`). For a multi-period control the first period's base time
    /// is returned, which is what a clock starts at.
    public var initialClockSeconds: TimeInterval? {
        guard let tag = loadedTags?["TimeControl"] else { return nil }
        return Self.timeControlBaseSeconds(tag)
    }

    /// Base seconds of the first period of a PGN `TimeControl` tag value.
    ///
    /// Covers the forms the PGN specification defines:
    ///
    /// | Form | Meaning | Result |
    /// |---|---|---|
    /// | `-` | no time control | `nil` |
    /// | `?` | unknown | `nil` |
    /// | `600` | sudden death, 600 seconds | `600` |
    /// | `300+5` | 300 seconds plus 5 per move | `300` |
    /// | `40/5400` | 5400 seconds for the first 40 moves | `5400` |
    /// | `40/5400+30` | the same, with increment | `5400` |
    /// | `*180` | sandclock / hourglass, 180 seconds | `180` |
    /// | `40/5400:1800:*60` | multi-period, `:`-separated | `5400` |
    static func timeControlBaseSeconds(_ tag: String) -> TimeInterval? {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "-", trimmed != "?" else { return nil }

        // Multi-period controls list their periods separated by ":"; the clock
        // starts on the first one.
        var period = Substring(trimmed)
        if let colon = period.firstIndex(of: ":") {
            period = period[period.startIndex..<colon]
        }

        // Hourglass ("*seconds") — the leading marker describes how the clock
        // behaves, not how much time it starts with.
        if period.hasPrefix("*") {
            period = period.dropFirst()
        }

        // "moves/seconds" — the base time is the part after the slash.
        if let slash = period.firstIndex(of: "/") {
            period = period[period.index(after: slash)...]
        }

        // Trailing "+increment" (or the rarer "-delay").
        if let sign = period.firstIndex(where: { $0 == "+" || $0 == "-" }) {
            period = period[period.startIndex..<sign]
        }

        guard let seconds = Int(period), seconds >= 0 else { return nil }
        return TimeInterval(seconds)
    }

    // MARK: - Players

    /// The PGN `White` or `Black` tag, or `nil` when the tag is absent.
    ///
    /// The value is returned as written. PGN uses `"?"` for an unknown player,
    /// and that is what a caller gets.
    public func playerName(for color: PieceColor) -> String? {
        let key = color == .white ? "White" : "Black"
        return loadedTags?[key]
    }

    /// The PGN `WhiteElo` or `BlackElo` tag as a number.
    ///
    /// `nil` when the tag is absent, empty, the PGN placeholder `"?"`, or not
    /// a number. `"0"` is a placeholder in practice and is also reported as
    /// `nil`; no rating list assigns it.
    public func elo(for color: PieceColor) -> Int? {
        let key = color == .white ? "WhiteElo" : "BlackElo"
        guard let raw = loadedTags?[key]?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, raw != "?",
              let value = Int(raw), value > 0 else {
            return nil
        }
        return value
    }
}
