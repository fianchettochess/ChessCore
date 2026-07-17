import Foundation

/// The pure game engine: the move tree, the current position, game state, and
/// navigation / PGN / FEN. A general chess game model — any board UI or analysis
/// surface builds on it.
///
/// This is the engine half of the app's `Game`. The board-interaction state
/// (selected square, pending promotion, pre-moves), the clock, sound/haptics,
/// and SwiftUI `@Observable` conformance live in the app's wrapper on the other
/// side of the boundary; here `apply(_:)` performs only the tree/position
/// mutation and the app layer adds clock/sound after it.
///
/// - Important: `Game` (and the `MoveNode` tree it owns) is a reference type and
///   is **not** thread-safe. Some node properties are memoized lazily on first
///   read, so even concurrent *reads* of the same game can race. Confine a `Game`
///   to a single actor/thread (it is intentionally not `Sendable`).
public final class Game {
    public private(set) var position: Position = .initial()
    public private(set) var startPosition: Position = .initial()

    public var rootChildren: [MoveNode] = []
    public private(set) var currentNode: MoveNode?

    /// Monotonically increasing counter bumped whenever the move-tree
    /// **structure** changes (new move, variation promote/delete, tree replaced
    /// via `loadPGN`/`newGame`). Navigation alone does NOT bump it — caches that
    /// derive O(n) tree data can key off this and skip recompute on navigation.
    public private(set) var treeMutationCount: Int = 0

    private func bumpTreeMutation() {
        treeMutationCount &+= 1
    }

    /// Monotonically increasing counter bumped whenever a **node property**
    /// changes (annotation, comment, engine results, move quality) without the
    /// tree structure changing. `MoveNode` is a plain reference type, so field
    /// writes are invisible to any observation layer — UIs key node-detail
    /// renders/caches off this counter instead (the companion to
    /// `treeMutationCount`, which covers structural edits only).
    public private(set) var nodePropertyVersion: Int = 0

    /// Bump `nodePropertyVersion` directly — for callers that batch many raw
    /// `MoveNode` field writes (e.g. a bulk annotation restore) and coalesce
    /// them into a single invalidation at the end.
    public func bumpNodeProperty() {
        nodePropertyVersion &+= 1
    }

    /// PGN tags carried with a loaded game; used by `exportPGN()`.
    public var loadedTags: PGNGame.OrderedTags?

    private var _cachedLegalMoves: [Move]?
    private var _cachedLegalMovesPosition: Position?
    private var _cachedGameStatePosition: Position?
    private var _cachedGameStateNodeID: UUID?
    private var _cachedGameStateValue: GameState?

    public init() {}

    private var allLegalMoves: [Move] {
        if let cached = _cachedLegalMoves, _cachedLegalMovesPosition == position {
            return cached
        }
        let moves = MoveGenerator.legalMoves(for: position)
        _cachedLegalMoves = moves
        _cachedLegalMovesPosition = position
        return moves
    }

    /// All legal moves for the current position, cached per position. Public so
    /// UI layers (square selection, pre-move validation) share this cache
    /// instead of maintaining their own `MoveGenerator.legalMoves` memo.
    public var legalMoves: [Move] { allLegalMoves }

    public var lastMove: Move? { currentNode?.move }

    public var canUndo: Bool { currentNode != nil }
    public var canRedo: Bool {
        if let node = currentNode {
            return node.mainContinuation != nil
        }
        return !rootChildren.isEmpty
    }

    /// Flat main line as `MoveRecord`s.
    public var moveHistory: [MoveRecord] {
        mainLine.map { MoveRecord(move: $0.move, notation: $0.notation, positionBefore: $0.positionBefore) }
    }

    public var currentMoveIndex: Int {
        guard let node = currentNode else { return -1 }
        return node.pathFromRoot().count - 1
    }

    public var mainLine: [MoveNode] {
        var nodes: [MoveNode] = []
        var node = rootChildren.first
        while let n = node {
            nodes.append(n)
            node = n.mainContinuation
        }
        return nodes
    }

    public var gameState: GameState {
        let nodeID = currentNode?.id
        if let cached = _cachedGameStateValue,
           _cachedGameStatePosition == position,
           _cachedGameStateNodeID == nodeID {
            return cached
        }
        let computed = computeGameState()
        _cachedGameStateValue = computed
        _cachedGameStatePosition = position
        _cachedGameStateNodeID = nodeID
        return computed
    }

    private func computeGameState() -> GameState {
        let moves = allLegalMoves
        let inCheck = MoveGenerator.isInCheck(position)

        if moves.isEmpty {
            return inCheck ? .checkmate : .stalemate
        }
        if position.halfmoveClock >= 100 {
            return .draw
        }
        if position.hasInsufficientMaterial {
            return .insufficientMaterial
        }
        if isThreefoldRepetition {
            return .repetition
        }
        return inCheck ? .check : .playing
    }

    private var isThreefoldRepetition: Bool {
        let key = position.repetitionKey
        var count = 1
        let limit = position.halfmoveClock

        // Walk node.positionBefore up the tree. The root node's positionBefore
        // IS startPosition, so exhausting the tree already counts the start
        // position — no post-loop startPosition check (it double-counted the
        // start whenever steps < limit, i.e. any FEN start with a nonzero
        // halfmove clock, declaring .repetition after only two occurrences).
        var node = currentNode
        var steps = 0
        while let n = node, steps < limit {
            if n.repetitionKey == key {
                count += 1
                if count >= 3 { return true }
            }
            node = n.parent
            steps += 1
        }

        return count >= 3
    }

    // MARK: - Navigation

    public func undoMove() {
        guard let node = currentNode else { return }
        position = node.positionBefore
        currentNode = node.parent
    }

    /// Retract (DELETE) the last `n` plies from the current line, moving the cursor
    /// back to the resulting position. Unlike `undoMove` — which only moves the
    /// cursor and leaves the moves in the tree as a forward continuation — this
    /// REMOVES the undone moves from the tree. A physical board take-back retracts
    /// them, so the next move played becomes the MAIN line rather than a variation
    /// hanging off the retracted move. No-op past the start of the line.
    public func retractLastPlies(_ n: Int) {
        var removedAny = false
        for _ in 0 ..< max(0, n) {
            guard let node = currentNode else { break }
            position = node.positionBefore
            currentNode = node.parent
            if let parent = node.parent {
                parent.children.removeAll { $0 === node }
            } else {
                rootChildren.removeAll { $0 === node }
            }
            removedAny = true
        }
        if removedAny { bumpTreeMutation() }
    }

    public func redoMove() {
        guard let next = currentNode?.mainContinuation ?? rootChildren.first else { return }
        navigateToNode(next)
    }

    public func navigateToNode(_ node: MoveNode) {
        position = node.positionAfter
        currentNode = node
    }

    public func navigateToStart() {
        position = startPosition
        currentNode = nil
    }

    public func newGame() {
        startPosition = .initial()
        position = .initial()
        rootChildren = []
        currentNode = nil
        loadedTags = nil
        bumpTreeMutation()
    }

    // MARK: - Applying moves

    /// Apply a pre-validated `Move` (promotion already chosen): updates the tree
    /// and position only. The app's wrapper adds clock/sound side-effects after.
    public func apply(_ move: Move) {
        makeMove(move)
    }

    public func applyMoveFromPGN(_ move: Move) {
        let notation = MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: allLegalMoves)
        let positionBefore = position
        let parentNode = currentNode
        let siblings = parentNode?.children ?? rootChildren
        let ply = (currentNode?.plyIndex ?? -1) + 1

        let node = MoveNode(move: move, notation: notation, positionBefore: positionBefore, parent: parentNode, plyIndex: ply)

        if siblings.isEmpty {
            if let parent = parentNode {
                parent.children.append(node)
            } else {
                rootChildren.append(node)
            }
        } else {
            if let existing = siblings.first(where: { $0.move == move }) {
                MoveGenerator.applyMoveUnchecked(&position, move)
                currentNode = existing
                return
            }
            if let parent = parentNode {
                parent.children.append(node)
            } else {
                rootChildren.append(node)
            }
        }

        MoveGenerator.applyMoveUnchecked(&position, move)
        currentNode = node
        bumpTreeMutation()
    }

    private func makeMove(_ move: Move) {
        let notation = MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: allLegalMoves)
        let positionBefore = position
        let parentNode = currentNode
        let siblings = parentNode?.children ?? rootChildren
        let ply = (currentNode?.plyIndex ?? -1) + 1

        if let existing = siblings.first(where: { $0.move == move }) {
            MoveGenerator.applyMoveUnchecked(&position, move)
            currentNode = existing
            return
        }

        let node = MoveNode(move: move, notation: notation, positionBefore: positionBefore, parent: parentNode, plyIndex: ply)

        if let parent = parentNode {
            parent.children.append(node)
        } else {
            rootChildren.append(node)
        }

        MoveGenerator.applyMoveUnchecked(&position, move)
        currentNode = node
        bumpTreeMutation()
    }

    // MARK: - Reconciliation (history-preserving position correction)

    /// Reconcile the game to the board state of `target` WITHOUT discarding move
    /// history when possible.
    ///
    /// If `target`'s piece placement and side-to-move are reachable from the current
    /// `position` by a short sequence of legal moves (≤ `maxPly`), those moves are
    /// applied through the tree (so `rootChildren` / `moveHistory` survive and simply
    /// extend) and `true` is returned. Returns `false` with **no mutation** when the
    /// target isn't reachable within `maxPly` — the caller can then decide whether to
    /// hard-reset via `loadFEN`.
    ///
    /// Useful whenever an external source of truth for the *position* (a sensing
    /// board, a remote game feed, a re-scanned diagram) runs ahead of the recorded
    /// line and the history must be caught up rather than thrown away. Matching is on
    /// placement + side-to-move (the observable board state); the applied moves derive
    /// the exact castling / en-passant rights, so the resulting tree position is
    /// internally consistent regardless of the target FEN's metadata fields.
    @discardableResult
    public func reconcile(toPlacementOf target: Position, maxPly: Int = 4) -> Bool {
        guard let path = reconcilePath(toPlacementOf: target, maxPly: maxPly) else { return false }
        for m in path { apply(m) }   // commit through the tree
        return true
    }

    /// The pure query half of `reconcile(toPlacementOf:)`: the legal-move
    /// sequence that reaches `target`'s placement from the current position,
    /// WITHOUT applying it. Returns `[]` when the placement already matches,
    /// `nil` when it is unreachable within `maxPly`. Callers that need
    /// per-move side effects (clock switching, haptics on a physical-board
    /// resync) can replay the path through their own `apply` wrapper.
    public func reconcilePath(toPlacementOf target: Position, maxPly: Int = 4) -> [Move]? {
        Self.reconcilePath(from: position, toPlacementOf: target, maxPly: maxPly)
    }

    /// Pure variant of ``reconcilePath(toPlacementOf:maxPly:)`` searching from an
    /// arbitrary start position. Retract-aware corrections probe each ancestor of
    /// the current line with this before falling back to a destructive reload.
    public static func reconcilePath(
        from start: Position,
        toPlacementOf target: Position,
        maxPly: Int = 4
    ) -> [Move]? {
        func placementKey(_ p: Position) -> String {
            let parts = p.fen.split(separator: " ")
            let placement = parts.first.map(String.init) ?? ""
            let sideToMove = parts.count >= 2 ? String(parts[1]) : ""
            return placement + " " + sideToMove
        }

        let targetKey = placementKey(target)
        if placementKey(start) == targetKey { return [] }   // already in sync

        // Breadth-first over legal-move sequences, deduped by placement so the search
        // stays small even at the default depth.
        var frontier: [(pos: Position, path: [Move])] = [(start, [])]
        var seen: Set<String> = [placementKey(start)]
        for _ in 0..<max(0, maxPly) {
            var next: [(pos: Position, path: [Move])] = []
            for (pos, path) in frontier {
                for move in MoveGenerator.legalMoves(for: pos) {
                    var advanced = pos
                    MoveGenerator.applyMoveUnchecked(&advanced, move)
                    let key = placementKey(advanced)
                    if key == targetKey {
                        return path + [move]
                    }
                    if seen.insert(key).inserted {
                        next.append((advanced, path + [move]))
                    }
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        return nil
    }

    // MARK: - Tree editing

    public func setAnnotation(_ annotation: MoveAnnotation?, on node: MoveNode) {
        node.annotation = annotation
        bumpNodeProperty()
    }

    public func setComment(_ comment: String?, on node: MoveNode) {
        node.comment = comment
        bumpNodeProperty()
    }

    public func clearComment(on node: MoveNode) {
        node.comment = nil
        bumpNodeProperty()
    }

    public func setEngineResults(on node: MoveNode, bestMoveUCI: String?, eval: String?) {
        node.engineBestMoveUCI = bestMoveUCI
        node.engineEval = eval
        bumpNodeProperty()
    }

    public func setMoveQuality(_ quality: MoveQuality?, accuracy: Double?, on node: MoveNode) {
        node.moveQuality = quality
        node.moveAccuracy = accuracy
        bumpNodeProperty()
    }

    /// Signal the end of a bulk annotation restore that wrote `MoveNode`
    /// fields directly — one coalesced `nodePropertyVersion` bump.
    public func finishAnnotationRestore() {
        bumpNodeProperty()
    }

    public func deleteFromNode(_ node: MoveNode) {
        if let parent = node.parent {
            parent.children.removeAll { $0 === node }
        } else {
            rootChildren.removeAll { $0 === node }
        }
        if isDescendantOrSelf(node, of: currentNode) {
            position = node.positionBefore
            currentNode = node.parent
        }
        bumpTreeMutation()
    }

    public func promoteVariation(_ node: MoveNode) {
        if let parent = node.parent {
            guard let index = parent.children.firstIndex(where: { $0 === node }), index > 0 else { return }
            parent.children.remove(at: index)
            parent.children.insert(node, at: 0)
        } else {
            guard let index = rootChildren.firstIndex(where: { $0 === node }), index > 0 else { return }
            rootChildren.remove(at: index)
            rootChildren.insert(node, at: 0)
        }
        bumpTreeMutation()
    }

    private func isDescendantOrSelf(_ ancestor: MoveNode, of node: MoveNode?) -> Bool {
        var current = node
        while let n = current {
            if n === ancestor { return true }
            current = n.parent
        }
        return false
    }

    // MARK: - PGN / FEN

    public func exportPGN() -> String {
        PGNExporter.export(game: self, tags: loadedTags)
    }

    public func loadPGN(_ pgn: String) -> Bool {
        let games = PGNParser.parse(pgn)
        guard let first = games.first else { return false }
        return loadPGNGame(first)
    }

    /// Restore a snapshot a drill saved on entry. Empty → fresh game.
    public func restoreDrillSnapshot(_ savedPGN: String) {
        if savedPGN.isEmpty {
            newGame()
        } else {
            _ = loadPGN(savedPGN)
        }
    }

    public func loadPGNGame(_ pgnGame: PGNGame) -> Bool {
        guard let loaded = PGNParser.loadGame(from: pgnGame) else { return false }
        startPosition = loaded.startPosition
        position = loaded.position
        rootChildren = loaded.rootChildren
        currentNode = loaded.currentNode
        loadedTags = pgnGame.tags.isEmpty ? nil : pgnGame.tags
        bumpTreeMutation()
        return true
    }

    /// Replace this game from a versioned, lossless move-tree snapshot.
    ///
    /// Materialization happens into local storage first. Any unsupported
    /// schema, malformed parent relation, illegal move, or resource-limit
    /// failure throws without changing the receiver.
    public func restore(
        from snapshot: GameTreeSnapshot,
        maximumNodes: Int = PGNParser.maximumMoveTreeNodes
    ) throws {
        let restored = try snapshot.materialize(
            maximumNodes: maximumNodes
        )
        startPosition = restored.startPosition
        position = restored.currentNode?.positionAfter
            ?? restored.startPosition
        rootChildren = restored.roots
        currentNode = restored.currentNode
        loadedTags = restored.loadedTags
        bumpTreeMutation()
    }

    public func loadFEN(_ fen: String) -> Bool {
        guard let pos = Position(fen: fen) else { return false }
        startPosition = pos
        position = pos
        rootChildren = []
        currentNode = nil
        loadedTags = nil
        bumpTreeMutation()
        return true
    }
}
