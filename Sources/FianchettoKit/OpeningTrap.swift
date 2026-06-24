import Foundation
import ChessCore

/// A drillable "knife-edge" opening position: the opponent just played
/// something unsound and there's a single response that holds.
///
/// JSON shape (matches `Resources/opening_traps.json`):
/// ```
/// {
///   "puzzleId": "...",              // Lichess puzzle ID, links back
///   "fen": "...",                   // FEN BEFORE the auto-played move
///   "moves": "uciSetup uciCorrect uciOppReply uciNext ...",
///   "rating": 980,                  // Lichess puzzle rating
///   "popularity": 95,               // Lichess puzzle popularity (0-100)
///   "themes": "mateIn1 oneMove opening ...",
///   "openingTags": "Italian_Game Italian_Game_Two_Knights",
///   "namedTrap": null | "Scholar's Mate",      // hand-curated
///   "note": null | "..."                       // hand-curated pedagogy
/// }
/// ```
///
/// Lichess puzzles list moves where the FIRST entry is the opponent's
/// auto-played move that creates the puzzle situation; the SECOND entry
/// is the solver's correct response. `fenAtTrap` resolves the FEN
/// forward by that first move so callers receive the position the user
/// is asked to defend.
public struct OpeningTrap: Codable, Sendable, Identifiable, Equatable {
    public let puzzleId: String
    public let fen: String
    public let moves: String
    public let rating: Int
    public let popularity: Int
    public let themes: String
    public let openingTags: String
    public let namedTrap: String?
    public let note: String?

    public var id: String { puzzleId }

    /// Convenience: the moves field split into a UCI array. Lichess
    /// joins them with a single space.
    public var moveList: [String] {
        moves.split(separator: " ").map(String.init)
    }

    /// The opponent's auto-played setup move. Lichess always lists this
    /// as the first entry; the puzzle position the solver acts from is
    /// the FEN advanced by this move.
    public var setupMoveUCI: String? { moveList.first }

    /// The defender's correct response — the solver's first move.
    public var correctMoveUCI: String? {
        let list = moveList
        return list.count >= 2 ? list[1] : nil
    }

    /// ECO family (e.g. "Italian_Game") — the first underscore-token of
    /// `openingTags`. The extraction script groups by this so the
    /// curated set has variety.
    public var ecoFamily: String {
        openingTags.split(separator: " ").first.map(String.init) ?? "Unknown"
    }

    /// Human-readable opening family name ("Italian Game" not
    /// "Italian_Game"). Used for grouping in the UI.
    public var openingFamilyDisplayName: String {
        ecoFamily.replacingOccurrences(of: "_", with: " ")
    }

    /// Coarse difficulty bucket derived from the Lichess `rating` field.
    /// The thresholds are intentionally generous — most of the
    /// rating-< 1700 puzzles we ship are "easy" or "medium" by chess
    /// standards. Tunable in one place if we recalibrate later.
    public var difficulty: Difficulty {
        switch rating {
        case ..<1200: .easy
        case 1200..<1600: .medium
        default: .hard
        }
    }

    public enum Difficulty: String, Sendable, CaseIterable, Codable {
        case easy, medium, hard

        var displayName: String {
            switch self {
            case .easy: "Easy"
            case .medium: "Medium"
            case .hard: "Hard"
            }
        }
    }

    /// The position the solver is presented with — i.e. `fen` advanced
    /// by the opponent's auto-played setup move. Returns the raw `fen`
    /// when the setup move is missing or fails to parse so callers
    /// still get a usable board (the solver just sees the wrong side
    /// to move in that pathological case).
    public var fenAtTrap: String {
        guard let setup = setupMoveUCI,
              var position = Position(fen: fen),
              let move = UCIParser.uciToMove(setup, in: position) else {
            return fen
        }
        MoveGenerator.applyMoveUnchecked(&position, move)
        return position.fen
    }
}
