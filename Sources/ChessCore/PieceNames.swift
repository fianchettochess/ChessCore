import Foundation

public extension PieceType {
    /// The English noun for the piece kind, lowercased: "king", "queen",
    /// "rook", "bishop", "knight", "pawn".
    ///
    /// These are the names the algebraic-notation letters abbreviate, so they
    /// are a property of the notation rather than of any user interface. They
    /// are **not localized** — a program presenting piece names in another
    /// language should map from the `PieceType` case rather than from this
    /// string.
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
