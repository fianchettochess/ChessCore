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
        let key = position.positionKey
        var count = 1
        let limit = position.halfmoveClock

        var node = currentNode
        var steps = 0
        while let n = node, steps < limit {
            if n.positionBefore.positionKey == key {
                count += 1
                if count >= 3 { return true }
            }
            node = n.parent
            steps += 1
        }

        if steps < limit && startPosition.positionKey == key {
            count += 1
        }
        return count >= 3
    }

    // MARK: - Navigation

    public func undoMove() {
        guard let node = currentNode else { return }
        position = node.positionBefore
        currentNode = node.parent
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

    // MARK: - Tree editing

    public func setAnnotation(_ annotation: MoveAnnotation?, on node: MoveNode) {
        node.annotation = annotation
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
