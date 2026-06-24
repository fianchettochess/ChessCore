import Foundation

/// Coarse static difficulty bucket for a tactics puzzle (from eval swing).
/// Seeds `TacticsRatingStore`'s per-puzzle Elo and labels puzzles before the
/// user has attempted them. (The full `TacticsExtractor` + `TacticsExtractionMode`
/// land with the tactics tranche; this shared type lives here so the stat stores
/// can reference it.)
public nonisolated enum PuzzleDifficulty: String, Sendable, CaseIterable, Codable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}
