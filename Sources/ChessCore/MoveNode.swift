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
    private var _id: UUID?

    /// Stable identity, generated lazily. PGN import builds many nodes that
    /// are never shown in UI (tactics re-parse, bulk analysis); deferring the
    /// `UUID()` draw until something actually reads `id` skips a per-node
    /// CSPRNG call on that path — measurable on Linux/Android, where `UUID()`
    /// is a `getrandom` syscall rather than Darwin's cheap arc4random. Once
    /// read the value is cached, so identity stays stable for the node's
    /// lifetime (SwiftUI diffing, the `gameState` cache key).
    public var id: UUID {
        if let cached = _id { return cached }
        let u = UUID()
        _id = u
        return u
    }

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

    /// The FEN full-move number of the position in which this move was played.
    ///
    /// Relative `plyIndex` is tree-local and always starts at zero, so deriving
    /// this value from ply parity resets mid-game FEN imports to move 1. The
    /// position already carries the authoritative anchored number.
    public var moveNumber: Int { positionBefore.fullmoveNumber }

    /// Color of the side that PLAYED this move. Derived from the position the
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

    private var _repetitionKey: String?

    /// `positionBefore.repetitionKey`, computed once. `positionBefore` is a
    /// `let`, so the cached key never goes stale; the threefold-repetition walk
    /// reuses it across the many game-state checks a game accrues.
    var repetitionKey: String {
        if let cached = _repetitionKey { return cached }
        let key = positionBefore.repetitionKey
        _repetitionKey = key
        return key
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

    deinit {
        // Iterative subtree teardown. `children` is a strong parent→child
        // chain; releasing a node naively recurses deinit per ply, and PGN
        // import has NO ply cap (a 2,000-ply shuffle game is ~12KB — the
        // stack overflows long before any byte limit bites). Detach each
        // uniquely-owned descendant's children before dropping it so its own
        // deinit sees an empty array and never recurses. Nodes something
        // else still holds are left intact — their remaining owner tears
        // them down the same way later.
        var pending = children
        children = []
        while !pending.isEmpty {
            var node = pending.removeLast()
            if isKnownUniquelyReferenced(&node) {
                pending.append(contentsOf: node.children)
                node.children = []
            }
        }
    }
}
