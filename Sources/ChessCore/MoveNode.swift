import Foundation

/// A node in a game's move tree — the move played, the position before it, and
/// its children (mainline first, then variations), plus per-move annotations and
/// engine metadata. A general chess game-tree type (like python-chess's
/// `GameNode` / chess.js history): any PGN tool or analysis surface needs it.
///
/// This is a PLAIN reference type. The app wraps/observes it for SwiftUI
/// (`@Observable`) on its side of the boundary; ChessCore keeps it observation-
/// free so it's portable. `positionAfter` is computed lazily via the move
/// generator and cached.
public final class MoveNode: Identifiable {
    public let id = UUID()
    public let move: Move
    public let notation: String
    public let positionBefore: Position
    public var children: [MoveNode] = []
    public weak var parent: MoveNode?
    public var plyIndex: Int
    public var annotation: MoveAnnotation?
    public var comment: String?
    public var engineBestMoveUCI: String?
    public var engineEval: String?
    public var moveQuality: MoveQuality?
    public var moveAccuracy: Double?
    public var clockSeconds: TimeInterval?

    public init(
        move: Move,
        notation: String,
        positionBefore: Position,
        parent: MoveNode?,
        plyIndex: Int,
        annotation: MoveAnnotation? = nil,
        comment: String? = nil
    ) {
        self.move = move
        self.notation = notation
        self.positionBefore = positionBefore
        self.parent = parent
        self.plyIndex = plyIndex
        self.annotation = annotation
        self.comment = comment
    }

    /// 1-based move number this node belongs to (plies 0,1 → move 1).
    /// Centralizes the `plyIndex / 2 + 1` off-by-one math.
    public var moveNumber: Int { plyIndex / 2 + 1 }

    /// Colour of the side that PLAYED this move. Derived from the position the
    /// move was made in — NOT ply parity, which misattributes every move of a
    /// FEN-setup game where Black moves first (ply 0 is then Black's move).
    public var moverColor: PieceColor { positionBefore.activeColor }

    private var _positionAfter: Position?

    public var positionAfter: Position {
        if let cached = _positionAfter { return cached }
        var pos = positionBefore
        MoveGenerator.applyMoveUnchecked(&pos, move)
        _positionAfter = pos
        return pos
    }

    public var mainContinuation: MoveNode? { children.first }
    public var variations: ArraySlice<MoveNode> { children.dropFirst() }
    public var hasVariations: Bool { children.count > 1 }

    public var isOnMainLine: Bool {
        guard let parent else { return true }
        return parent.children.first === self && parent.isOnMainLine
    }

    public func pathFromRoot() -> [MoveNode] {
        var path: [MoveNode] = []
        var node: MoveNode? = self
        while let n = node {
            path.append(n)
            node = n.parent
        }
        return path.reversed()
    }
}
