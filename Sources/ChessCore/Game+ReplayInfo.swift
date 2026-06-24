import Foundation

/// Replay-time projections of `Game`'s loaded PGN tags + per-node
/// clock annotations. Both the regular layout's board chrome and the
/// compact-landscape side cards render the same player metadata
/// (name / Elo / clock) — having a shared accessor here means the two
/// call sites can't drift, and any future replay surface (e.g. a
/// Stats-tab game preview) reuses the same logic.
extension Game {
    /// True if the loaded game has annotated per-ply clock times — the
    /// first child of the root carries the `{[%clk ...]}` value from
    /// the source PGN if any.
    public var hasReplayClockData: Bool {
        rootChildren.first?.clockSeconds != nil
    }

    /// Replay clock state at the currently-selected node: (white time,
    /// black time, side-to-move). Times fall back to the PGN
    /// `TimeControl` base when the corresponding side hasn't made a
    /// move with a clock annotation yet.
    public var replayClockTimes: (white: TimeInterval?, black: TimeInterval?, active: PieceColor) {
        let active = position.activeColor

        guard hasReplayClockData else {
            return (nil, nil, active)
        }

        if currentNode == nil {
            let initial = replayInitialClockTime
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

        if whiteTime == nil { whiteTime = replayInitialClockTime }
        if blackTime == nil { blackTime = replayInitialClockTime }

        return (whiteTime, blackTime, active)
    }

    /// Player name from the PGN `White` / `Black` tag, or `nil` when
    /// the tag is absent.
    public func replayPlayerName(for color: PieceColor) -> String? {
        let key = color == .white ? "White" : "Black"
        return loadedTags?[key]
    }

    /// PGN-tag Elo for the requested side. Returns `nil` when the tag
    /// is absent, empty, or the placeholder "?" / "0", so callers can
    /// omit the badge entirely rather than render a meaningless value.
    public func replayPlayerELO(for color: PieceColor) -> String? {
        let key = color == .white ? "WhiteElo" : "BlackElo"
        guard let raw = loadedTags?[key], !raw.isEmpty, raw != "?", raw != "0" else {
            return nil
        }
        return raw
    }

    /// Whether the loaded game has any tag-derived player metadata for
    /// `color` — drives whether the player-info panel should render
    /// even when there's no clock data.
    public func hasReplayPlayerInfo(for color: PieceColor) -> Bool {
        if let name = replayPlayerName(for: color), !name.isEmpty, name != "?" { return true }
        return replayPlayerELO(for: color) != nil
    }

    /// Initial clock time parsed from the PGN `TimeControl` tag, used
    /// when the replay hasn't yet reached a node with an explicit clock
    /// annotation for one of the sides.
    public var replayInitialClockTime: TimeInterval? {
        guard let tc = loadedTags?["TimeControl"],
              !tc.isEmpty, tc != "-" else { return nil }
        let base = tc.split(separator: "+").first.flatMap { Int($0) }
        return base.map { TimeInterval($0) }
    }
}
