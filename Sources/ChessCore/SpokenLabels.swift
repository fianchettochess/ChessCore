import Foundation

// Spoken / natural-language phrasing for domain types. Pure String output, no
// UI framework dependency — shared by both apps' accessibility labels
// (VoiceOver / TalkBack) and the Square Off correction prose, so the wording
// lives in exactly one place instead of being re-inlined per view/platform.

public extension PieceType {
    /// Lowercase spoken noun for the piece kind ("knight", "queen").
    var displayName: String {
        switch self {
        case .king:   return "king"
        case .queen:  return "queen"
        case .rook:   return "rook"
        case .bishop: return "bishop"
        case .knight: return "knight"
        case .pawn:   return "pawn"
        }
    }
}

public extension Piece {
    /// Human-readable identity, e.g. "White knight" / "Black queen". Used by
    /// accessibility square labels and identity-aware Square Off corrections.
    var descriptiveName: String {
        let colorWord = color == .white ? "White" : "Black"
        return "\(colorWord) \(type.displayName)"
    }
}

public extension MoveNode {
    /// Natural-language spoken label for accessibility (VoiceOver / TalkBack).
    /// Uses `positionBefore.fullmoveNumber` so anchored repertoires announce the
    /// correct mid-game number rather than restarting at 1; a "..." prefix marks
    /// Black moves because the visual white/black column split is invisible to a
    /// screen reader. (anchor move-numbering fix 2026-06-27)
    func spokenLabel(isCurrent: Bool) -> String {
        let moveNumber = positionBefore.fullmoveNumber
        let isBlack = positionBefore.activeColor == .black
        let prefix = isBlack ? "\(moveNumber)..." : "\(moveNumber)."
        var label = "\(prefix) \(notation)"
        if let annotation { label += ", \(annotation.rawValue)" }
        if isCurrent { label += ", current" }
        return label
    }
}
