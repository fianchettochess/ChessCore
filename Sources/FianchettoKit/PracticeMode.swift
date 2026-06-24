import Foundation

/// The Train drills, keyed by stable raw values used for routing, deep-link
/// tokens, and per-drill progress keys. (The app's `displayName` — e.g.
/// "Openings" for `.repertoire` — is presentation and stays app-side; Android
/// supplies its own labels.)
public nonisolated enum PracticeMode: String, Sendable, CaseIterable, Codable {
    case study = "Study"
    case repertoire = "Repertoire"
    case tactics = "Tactics"
    case traps = "Traps"
    case endgame = "Endgames"
    /// Refute opponents' unsound replies sourced from the repertoire.
    case punish = "Punish"
}
