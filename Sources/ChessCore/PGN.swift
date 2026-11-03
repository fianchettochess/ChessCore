import Foundation

// `PGNParser` is split across two files. The pure tokenization /
// snapshot path lives in `PGNTokenizer.swift` for consumers that do not need
// to materialize a live tree. This file carries the `Game`-bound entry points (`loadGame`)
// and the exporter — anything that materialises or walks the live
// `MoveNode` tree.

/// A move inferred in place of an unreadable main-line token.
public struct PGNImputedMove {
    public let originalToken: String
    public let notation: String
    public let plyIndex: Int
}

/// The order used to interpret nested variations in a complete movetext.
public enum PGNVariationOrder: Sendable {
    case standard
    case alternativesBeforeContinuation
}

/// Information a storage caller needs before replacing the original movetext.
/// Callers building `PGNGame` by hand must carry diagnostics and written offsets.
public struct PGNLenientLoadReport {
    public let game: Game
    /// First recognized annotation written for each annotated node, in token order.
    /// The tree's annotation retains its existing last-wins behavior.
    public let firstAnnotationsByNodeID: [UUID: MoveAnnotation]
    public let imputedMoves: [PGNImputedMove]
    public let droppedMoveTokens: [String]
    /// Text that the tree cannot safely carry through a rewrite.
    public let uncarriedText: [String]
    /// Subset of uncarriedText before the first non-comment token, in token order and raw token text.
    public let leadingComments: [String]
    /// Prose at variation heads attached to their branch point.
    public let headCommentsMovedToBranchPoint: Int
    public let hasUnterminatedBraceComment: Bool
    /// Whether the loaded main line differs from a replay of depth-zero tokens.
    public let mainLineDiffersFromSnapshot: Bool
    public let exceedsExportVariationDepth: Bool
    public let hasUnrecognizedSetupTag: Bool
    public let hasInconsistentMoveNumbers: Bool
    /// Order used by the tree builder. Depth-one variations always use standard placement.
    public let variationOrder: PGNVariationOrder
    /// Placement cannot safely be inferred, contradicts written numbers, or was not checked.
    public let hasUncertainVariationPlacement: Bool

    /// Whether rewriting loses no text that lacks a tree home.
    /// An annotation pass may still replace authored best moves, evals, or glyphs.
    /// Tags with names on one line and no double quote are preserved by the exporter.
    /// For a stored movetext row, use `tokenizeWithVariationDiagnostics`, not `parse(text).first`:
    /// parsing may split at a bracket-only line or skip an oversized record.
    public var canReplaceStoredText: Bool {
        uncarriedText.isEmpty && droppedMoveTokens.isEmpty && !hasUnterminatedBraceComment && !mainLineDiffersFromSnapshot
            && !exceedsExportVariationDepth && !hasUnrecognizedSetupTag && !hasInconsistentMoveNumbers && !hasUncertainVariationPlacement && imputedMoves.isEmpty
    }

    /// Whether rewriting is safe if the caller preserves the leading comments from the stored row.
    public var canReplaceStoredTextKeepingLeadingComments: Bool {
        uncarriedText.count == leadingComments.count && droppedMoveTokens.isEmpty && !hasUnterminatedBraceComment && !mainLineDiffersFromSnapshot
            && !exceedsExportVariationDepth && !hasUnrecognizedSetupTag && !hasInconsistentMoveNumbers && !hasUncertainVariationPlacement && imputedMoves.isEmpty
    }
}

private final class PGNLoadAccounting {
    var firstAnnotationsByNodeID: [UUID: MoveAnnotation] = [:]
    func record(_ annotation: MoveAnnotation?, for node: MoveNode) {
        guard let annotation else { return }
        if firstAnnotationsByNodeID[node.id] == nil { firstAnnotationsByNodeID[node.id] = annotation }
    }
    var dropped: [String] = []
    var uncarried: [String] = []
    var leading: [String] = []
    var headComments = 0
    var order: PGNVariationOrder = .standard
    var uncertain = false
}

extension PGNParser {

    // A bare destination can be read as a pawn capture, but exporting it
    // adds the origin file and changes the stored token.
    private static func isInferredPawnCapture(_ san: String, _ move: Move) -> Bool {
        guard move.piece == .pawn, move.from.file != move.to.file else { return false }
        var word = san
        while let last = word.last, "+#!?".contains(last) { word.removeLast() }
        guard word.count >= 2, Square(algebraic: String(word.prefix(2))) != nil else { return false }
        let rest = word.dropFirst(2)
        return rest.isEmpty || rest.first == "=" || (rest.count == 1 && rest.first.map { "QRBNqrbn".contains($0) } == true)
    }

    /// Maximum number of `MoveNode` objects materialized for one PGN game,
    /// including variations. This is deliberately far above practical game
    /// trees while bounding adversarial, compact repetition input.
    public static let maximumMoveTreeNodes = 65_536
    static let maximumVariationDepth = 1_024

    public static func loadGame(from pgn: String) -> Game? {
        let pgnGames = parse(pgn)
        guard let pgnGame = pgnGames.first else { return nil }
        return loadGame(from: pgnGame)
    }

    /// Lenient materialization, which stored games rely on to stay openable.
    ///
    /// A main-line token that cannot be played is passed over without a
    /// diagnostic, so the result may not be the game that was written; a game
    /// holding only the flat `moves` list stops at that token instead. Use
    /// ``loadGame(from:maximumTreeNodes:)`` or ``parseMainLineSnapshot(from:pliesLimit:)``
    /// to learn that a game has such a token.
    public static func loadGame(from pgnGame: PGNGame) -> Game? {
        try? materialize(
            pgnGame,
            maximumTreeNodes: maximumMoveTreeNodes,
            rejectsUnparseableMainLine: false
        )
    }

    /// Load with the compatibility behavior and report moves absent from its tree.
    /// Preserve the original text whenever this report indicates loss or uncertainty.
    public static func loadGameWithReport(from pgnGame: PGNGame) -> PGNLenientLoadReport? {
        let accounting = PGNLoadAccounting()
        guard let game = try? materialize(pgnGame, maximumTreeNodes: maximumMoveTreeNodes,
                                          rejectsUnparseableMainLine: false, accounting: accounting) else { return nil }
        return PGNLenientLoadReport(game: game, firstAnnotationsByNodeID: accounting.firstAnnotationsByNodeID, imputedMoves: [], droppedMoveTokens: accounting.dropped,
            uncarriedText: accounting.uncarried, leadingComments: accounting.leading, headCommentsMovedToBranchPoint: accounting.headComments,
            hasUnterminatedBraceComment: pgnGame.diagnostics.contains(.unterminatedBraceComment),
            mainLineDiffersFromSnapshot: mainLineDiffers(pgnGame, game: game),
            exceedsExportVariationDepth: exceedsExportDepth(game),
            hasUnrecognizedSetupTag: pgnGame.tags.orderedKeys.contains { $0 != "FEN" && $0.uppercased() == "FEN" },
            hasInconsistentMoveNumbers: pgnGame.hasInconsistentMoveNumbers,
            variationOrder: accounting.order, hasUncertainVariationPlacement: accounting.uncertain)
    }

    /// Opt in to conservative main-line repair. An unreadable token is replaced
    /// only if exactly one legal move permits every subsequent main-line move.
    /// Retain the original movetext: every substitution is reported, and legal
    /// continuation alone cannot establish the move that was actually played.
    /// An imputation is a reading for display, never to be stored. A stray
    /// well-formed move or a legally corrupted move can yield a wrong unique
    /// reading, for example `...19. Qd1 Qb3 20. Qb1 Nc3` with an extra Qd1.
    public static func loadGameWithImputation(from pgnGame: PGNGame) -> PGNLenientLoadReport? {
        guard var position = startingPosition(for: pgnGame) else { return nil }
        let flat = pgnGame.moveTokens.isEmpty
        var tokens = flat ? pgnGame.moves.map { PGNToken.move($0) } : pgnGame.moveTokens
        var indices: [Int] = []
        var depth = 0
        for (index, token) in tokens.enumerated() {
            switch token {
            case .variationStart: depth += 1
            case .variationEnd: depth = max(0, depth - 1)
            case .move(let san):
                if depth == 0 && !isReportNoise(san) {
                    indices.append(index)
                    if indices.count > maximumMoveTreeNodes { return nil }
                }
            default: break
            }
        }
        var imputed: [PGNImputedMove] = []
        var ply = 0
        for (offset, index) in indices.enumerated() {
            guard case .move(let san) = tokens[index] else { continue }
            let legal = MoveGenerator.legalMoves(for: position)
            if let move = parseMove(readableMoveWord(san).san, in: position, legalMoves: legal) {
                MoveGenerator.applyMoveUnchecked(&position, move)
                ply += 1
                continue
            }
            let cleaned = MoveAnnotation.extract(from: san).cleaned
            guard (2...7).contains(cleaned.count), hasImputationShape(cleaned), let last = cleaned.last,
                  ("1"..."8").contains(String(last)), indices.count - offset - 1 >= 2 else { break }
            func tailReplays(_ start: Position) -> Bool {
                var trial = start
                for following in indices.dropFirst(offset + 1) {
                    guard case .move(let next) = tokens[following],
                          let move = parseMoveWord(next, in: trial) else { return false }
                    MoveGenerator.applyMoveUnchecked(&trial, move)
                }
                return true
            }
            guard !tailReplays(position) else { break }
            var survivors: [Move] = []
            for candidate in legal {
                var trial = position
                MoveGenerator.applyMoveUnchecked(&trial, candidate)
                if tailReplays(trial) { survivors.append(candidate) }
                if survivors.count > 1 { break }
            }
            if survivors.count == 1, let move = survivors.first {
                let notation = MoveGenerator.algebraicNotation(for: move, in: position, legalMoves: legal)
                tokens[index] = .move(notation)
                imputed.append(PGNImputedMove(originalToken: san, notation: notation, plyIndex: ply))
                MoveGenerator.applyMoveUnchecked(&position, move)
                ply += 1
            } else {
                // Without a unique replacement, later plies have no reliable board.
                break
            }
        }
        var repaired = pgnGame
        if flat {
            repaired.moves = tokens.compactMap { if case .move(let san) = $0 { return san }; return nil }
        } else {
            repaired.moveTokens = tokens
        }
        guard let report = loadGameWithReport(from: repaired) else { return nil }
        guard report.droppedMoveTokens.isEmpty && !report.mainLineDiffersFromSnapshot else {
            return loadGameWithReport(from: pgnGame)
        }
        return PGNLenientLoadReport(game: report.game, firstAnnotationsByNodeID: report.firstAnnotationsByNodeID, imputedMoves: imputed,
            droppedMoveTokens: report.droppedMoveTokens,
            uncarriedText: report.uncarriedText, leadingComments: report.leadingComments, headCommentsMovedToBranchPoint: report.headCommentsMovedToBranchPoint,
            hasUnterminatedBraceComment: report.hasUnterminatedBraceComment,
            mainLineDiffersFromSnapshot: report.mainLineDiffersFromSnapshot,
            exceedsExportVariationDepth: report.exceedsExportVariationDepth,
            hasUnrecognizedSetupTag: report.hasUnrecognizedSetupTag,
            hasInconsistentMoveNumbers: report.hasInconsistentMoveNumbers,
            variationOrder: report.variationOrder, hasUncertainVariationPlacement: report.hasUncertainVariationPlacement)
    }

    static func hasImputationShape(_ token: String) -> Bool {
        guard let first = token.utf8.first,
              (65...90).contains(first) || (97...122).contains(first) else { return false }
        return token.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0)
            || (48...57).contains($0) || [61, 45, 43].contains($0) }
    }

    /// Materialize one parsed PGN with an explicit whole-tree resource budget.
    ///
    /// Unlike the compatibility overload, this surface reports a limit breach
    /// as ``PGNDiagnostic/moveTreeNodeLimitExceeded(maximumNodes:)`` and a
    /// main-line token it cannot play as
    /// ``PGNDiagnostic/unparseableMainlineMove(san:plyIndex:)``, the same
    /// diagnostic the snapshot path reports. No partial game escapes: the local
    /// tree is released as the error unwinds.
    public static func loadGame(
        from pgnGame: PGNGame,
        maximumTreeNodes: Int
    ) throws -> Game {
        try materialize(
            pgnGame,
            maximumTreeNodes: maximumTreeNodes,
            rejectsUnparseableMainLine: true
        )
    }

    // The compatibility loader also skips these unplayable main-line words.
    // They are notation, not moves, even where the legacy variation loader
    // abandons a line on encountering them.
    /// True for a word in move text that is notation, not a move: markup such as
    /// `N`, `+=` or `e.p.`, a detached glyph, a bare move number, or a result.
    /// A caller replaying tokens by hand skips these, as the loaders do.
    public static func isMoveTextNotation(_ san: String) -> Bool {
        isReportNoise(san)
    }

    static func isReportNoise(_ san: String) -> Bool {
        let cleaned = MoveAnnotation.extract(from: san).cleaned
        return isMoveTextNoise(cleaned) || (!cleaned.isEmpty && cleaned.allSatisfy { $0.isASCII && $0.isNumber })
            || isNumberedEllipsis(cleaned)
            || cleaned == "1/2" || cleaned == "½-½"
    }

    private static func isNumberedEllipsis(_ word: String) -> Bool {
        guard word.last == "…" else { return false }
        let number = word.dropLast()
        return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func mainLineDiffers(_ input: PGNGame, game: Game) -> Bool {
        var position = game.startPosition
        var moves: [Move] = []
        var depth = 0
        let tokens = input.moveTokens.isEmpty ? input.moves.map { PGNToken.move($0) } : input.moveTokens
        for token in tokens {
            switch token {
            case .variationStart: depth += 1
            case .variationEnd: depth = max(0, depth - 1)
            case .move(let san) where depth == 0 && !isReportNoise(san):
                guard let move = parseMoveWord(san, in: position) else { return true }
                moves.append(move)
                MoveGenerator.applyMoveUnchecked(&position, move)
            default: break
            }
        }
        return moves != game.mainLine.map(\.move)
    }

    private static func exceedsExportDepth(_ game: Game) -> Bool {
        var pending: [([MoveNode], Int)] = [(game.rootChildren, 0)]
        while let (children, depth) = pending.popLast() {
            if children.count > 1 {
                if depth + 1 >= PGNExporter.maxVariationDepth { return true }
                for node in children.dropFirst() { pending.append(([node], depth + 1)) }
            }
            if let first = children.first { pending.append((first.children, depth)) }
        }
        return false
    }

    private static func materialize(
        _ pgnGame: PGNGame,
        maximumTreeNodes: Int,
        rejectsUnparseableMainLine: Bool,
        accounting: PGNLoadAccounting? = nil
    ) throws -> Game {
        // A non-positive node budget admits no tree at all; surface it as a
        // catchable diagnostic rather than trapping a public throwing API.
        guard maximumTreeNodes > 0 else {
            throw PGNDiagnostic.moveTreeNodeLimitExceeded(maximumNodes: maximumTreeNodes)
        }
        let game = Game()

        // Share the snapshot parser's FEN interpretation so the two public PGN
        // paths cannot drift on empty, valid, or invalid setup tags.
        guard let startPosition = startingPosition(for: pgnGame) else {
            throw PGNDiagnostic.invalidFEN(pgnGame.tags["FEN"] ?? "")
        }
        if pgnGame.tags["FEN"]?.isEmpty == false {
            guard game.loadFEN(startPosition.fen) else {
                throw PGNDiagnostic.invalidFEN(pgnGame.tags["FEN"] ?? "")
            }
        }

        if pgnGame.moveTokens.isEmpty {
            var materializedNodeCount = 0
            for (index, san) in pgnGame.moves.enumerated() {
                if isMoveTextNoise(MoveAnnotation.extract(from: san).cleaned) { continue }
                let word = readableMoveWord(san)
                guard let move = parseMove(word.san, in: game.position) else {
                    if rejectsUnparseableMainLine {
                        throw PGNDiagnostic.unparseableMainlineMove(
                            san: MoveAnnotation.extract(from: san).cleaned,
                            plyIndex: materializedNodeCount
                        )
                    }
                    accounting?.dropped.append(contentsOf: pgnGame.moves[index...].filter {
                        !isReportNoise($0)
                    })
                    return game
                }
                guard materializedNodeCount < maximumTreeNodes else {
                    throw PGNDiagnostic.moveTreeNodeLimitExceeded(
                        maximumNodes: maximumTreeNodes
                    )
                }
                if word.altered || isInferredPawnCapture(word.san, move) { accounting?.uncarried.append(san) }
                game.applyMoveFromPGN(move)
                if let node = game.currentNode {
                    let annotation = MoveAnnotation.extract(from: word.san).annotation ?? word.nag.flatMap(MoveAnnotation.from(nag:))
                    accounting?.record(annotation, for: node)
                    if word.altered, let annotation { node.annotation = annotation }
                }
                materializedNodeCount += 1
            }
        } else {
            let decision = variationDecision(tokens: pgnGame.moveTokens, offsets: pgnGame.variationWrittenOffsets,
                                             start: startPosition)
            accounting?.order = decision.order
            accounting?.uncertain = decision.uncertain
            try buildTree(
                game: game,
                order: decision.order,
                nestedMoves: decision.nestedMoves,
                tokens: pgnGame.moveTokens,
                maximumNodes: maximumTreeNodes,
                rejectsUnparseableMainLine: rejectsUnparseableMainLine,
                accounting: accounting
            )
        }

        return game
    }

    private static func buildTree(
        game: Game,
        order: PGNVariationOrder,
        nestedMoves: Set<Int>,
        tokens: [PGNToken],
        maximumNodes: Int,
        rejectsUnparseableMainLine: Bool,
        accounting: PGNLoadAccounting?
    ) throws {
        var nodeStack: [MoveNode?] = [nil]
        // Parallel to `nodeStack`: the frame's next move continues a line whose
        // alternatives were read first.
        var continuationIsPending = [false]
        var frameHasMove = [false]
        var materializedNodeCount = 0
        // Open parentheses in the variation being abandoned, its own included.
        // Its own close still reaches the switch, to pop its frame.
        var abandonedDepth = 0
        var skippedDepth = 0
        var sawNonComment = false

        for (tokenIndex, token) in tokens.enumerated() {
            if case .comment = token {} else { sawNonComment = true }
            if skippedDepth > 0 {
                if case .move(let san) = token, !isReportNoise(san) { accounting?.dropped.append(san) }
                if case .variationStart = token { skippedDepth += 1 }
                if case .variationEnd = token { skippedDepth -= 1 }
                continue
            }
            if abandonedDepth > 0 {
                switch token {
                case .comment(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty: accounting?.uncarried.append(text)
                case .nag(let n): accounting?.uncarried.append("$\(n)")
                case .move(let san) where isReportNoise(san): accounting?.uncarried.append(san)
                default: break
                }
                if case .move(let san) = token, !isReportNoise(san) {
                    accounting?.dropped.append(san)
                }
                if case .variationStart = token { abandonedDepth += 1 }
                if case .variationEnd = token { abandonedDepth -= 1 }
                if abandonedDepth > 0 { continue }
            }
            switch token {
            case .move(let san):
                if isReportNoise(san) {
                    let (cleanedSan, annotation) = MoveAnnotation.extract(from: san)
                    let glyphWords: Set<String> = ["=", "+=", "=+", "+/=", "=/+", "+/-", "-/+", "+-", "-+", "∞", "±", "∓", "⩲", "⩱", "□", "N", "D"]
                    if glyphWords.contains(san) || (cleanedSan.isEmpty && annotation != nil) || (nodeStack.count > 1 && !san.isEmpty && san.allSatisfy { $0.isASCII && $0.isNumber }) || isNumberedEllipsis(san) { accounting?.uncarried.append(san) }
                    continue
                }
                let word = readableMoveWord(san)
                let (cleanedSan, writtenAnnotation) = MoveAnnotation.extract(from: word.san)
                let annotation = writtenAnnotation ?? word.nag.flatMap(MoveAnnotation.from(nag:))
                let currentPos: Position
                if let last = nodeStack.last, let node = last {
                    currentPos = node.positionAfter
                } else {
                    currentPos = game.startPosition
                }
                // Generate the legal-move list ONCE and thread it into both the
                // SAN parse and the canonical-notation derivation.
                let legal = MoveGenerator.legalMoves(for: currentPos)
                guard let move = parseMove(cleanedSan, in: currentPos, legalMoves: legal) else {
                    if !isReportNoise(san) { accounting?.dropped.append(san) }
                    // The rest of a variation depends on the move it could not
                    // read, so replaying it would invent a line.
                    if nodeStack.count > 1 {
                        abandonedDepth = 1
                    } else if rejectsUnparseableMainLine {
                        throw PGNDiagnostic.unparseableMainlineMove(
                            san: cleanedSan,
                            plyIndex: (nodeStack.last??.plyIndex ?? -1) + 1
                        )
                    }
                    continue
                }

                if word.altered || isInferredPawnCapture(cleanedSan, move) { accounting?.uncarried.append(san) }

                let parentNode = nodeStack.last ?? nil
                let siblings = parentNode?.children ?? game.rootChildren
                let ply = (parentNode?.plyIndex ?? -1) + 1
                defer {
                    if continuationIsPending[continuationIsPending.count - 1] {
                        continuationIsPending[continuationIsPending.count - 1] = false
                        if let parentNode, let placed = nodeStack[nodeStack.count - 1],
                           let index = parentNode.children.firstIndex(where: { $0 === placed }) {
                            parentNode.children.insert(parentNode.children.remove(at: index), at: 0)
                        }
                    }
                }

                frameHasMove[frameHasMove.count - 1] = true
                if let existing = siblings.first(where: { $0.move == move }) {
                    accounting?.record(annotation, for: existing)
                    if let annotation, let old = existing.annotation, old != annotation { accounting?.uncarried.append(san) }
                    if let annotation { existing.annotation = annotation }
                    nodeStack[nodeStack.count - 1] = existing
                } else {
                    guard materializedNodeCount < maximumNodes else {
                        throw PGNDiagnostic.moveTreeNodeLimitExceeded(
                            maximumNodes: maximumNodes
                        )
                    }
                    let notation = MoveGenerator.algebraicNotation(for: move, in: currentPos, legalMoves: legal)
                    let newNode = MoveNode(move: move, notation: notation, positionBefore: currentPos, parent: parentNode, plyIndex: ply, annotation: annotation)
                    accounting?.record(annotation, for: newNode)
                    if let parent = parentNode {
                        parent.children.append(newNode)
                    } else {
                        game.rootChildren.append(newNode)
                    }
                    nodeStack[nodeStack.count - 1] = newNode
                    materializedNodeCount += 1
                }

            case .nag(let number):
                let node = nodeStack.last ?? nil
                let mapped = MoveAnnotation.from(nag: number)
                if mapped == nil || node == nil || !frameHasMove[frameHasMove.count - 1] || (node?.annotation != nil && node?.annotation != mapped) {
                    accounting?.uncarried.append("$\(number)")
                }
                if let annotation = MoveAnnotation.from(nag: number),
                   let last = nodeStack.last, let currentNode = last {
                    accounting?.record(annotation, for: currentNode)
                    currentNode.annotation = annotation
                }

            case .variationStart:
                if nodeStack.count > maximumVariationDepth {
                    skippedDepth = 1
                    continue
                }
                let currentNode = nodeStack.last ?? nil
                let branchPoint = currentNode?.parent
                if nestedMoves.contains(tokenIndex) && order == .alternativesBeforeContinuation {
                    continuationIsPending[continuationIsPending.count - 1] = true
                    nodeStack.append(currentNode)
                } else {
                    nodeStack.append(branchPoint)
                }
                continuationIsPending.append(false)
                frameHasMove.append(false)

            case .variationEnd:
                if nodeStack.count > 1 {
                    nodeStack.removeLast()
                    continuationIsPending.removeLast()
                    frameHasMove.removeLast()
                }

            case .comment(let text):
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let accounting, !trimmedText.isEmpty {
                    if let node = nodeStack.last ?? nil {
                        let parsed = parseEngineComment(trimmedText)
                        let atHead = nodeStack.count > 1 && !frameHasMove[frameHasMove.count - 1]
                        if atHead {
                            if parsed.eval != nil || parsed.bestMove != nil || parsed.clockSeconds != nil {
                                accounting.uncarried.append(text)
                            } else { accounting.headComments += 1 }
                        }
                        if commentLosesText(trimmedText, node: node) { accounting.uncarried.append(text) }
                    } else {
                        accounting.uncarried.append(text)
                        let parsed = parseEngineComment(trimmedText)
                        if !sawNonComment && parsed.eval == nil && parsed.bestMove == nil {
                            accounting.leading.append(text)
                        }
                    }
                }
                if let last = nodeStack.last, let currentNode = last {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        let parsed = Self.parseEngineComment(trimmed)
                        if let eval = parsed.eval { currentNode.engineEval = eval }
                        if let best = parsed.bestMove {
                            if let uci = UCIParser.sanToUCI(best, in: currentNode.positionBefore) {
                                currentNode.engineBestMoveUCI = uci
                            } else {
                                currentNode.engineBestMoveUCI = best
                            }
                        }
                        if let clock = parsed.clockSeconds { currentNode.clockSeconds = clock }
                        if let userComment = parsed.comment {
                            if let existing = currentNode.comment {
                                currentNode.comment = existing + " " + userComment
                            } else {
                                currentNode.comment = userComment
                            }
                        }
                    }
                }
            }
        }

        let mainLine = game.mainLine
        if let lastNode = mainLine.last {
            game.navigateToNode(lastNode)
        }
    }

    // Mirrors the comment reader only for loss accounting; it never changes what it reads.
    private static func commentLosesText(_ text: String, node: MoveNode) -> Bool {
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        func count(_ marker: String) -> Int { text.components(separatedBy: marker).count - 1 }
        let parsed = parseEngineComment(text)
        if count("[%eval") > 1 || count("[%clk") > 1 { return true }
        if matches(text, #"\[%clk\s+\d+:\d{2}:\d{2}(?:\.\d+)?\]"#) && parsed.clockSeconds == nil { return true }
        if let best = parsed.bestMove, !matches(best, #"^(?:[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=?[QRBNqrbn])?|O-O(?:-O)?|0-0(?:-0)?|[a-h][1-8][a-h][1-8][qrbn]?)[+#]?[!?]*$"#) { return true }
        if let eval = parsed.eval, let old = node.engineEval, eval != old { return true }
        if let clock = parsed.clockSeconds, let old = node.clockSeconds, clock != old { return true }
        if let best = parsed.bestMove, let old = node.engineBestMoveUCI,
           (UCIParser.sanToUCI(best, in: node.positionBefore) ?? best) != old { return true }
        // Strip tags first: a clock and a bare mate can share a semicolon part.
        let withoutTags = text.replacingOccurrences(of: #"\[%(?:eval|clk)[^\]]*\]"#, with: "", options: .regularExpression)
        var evals: [String] = []
        var bests: [String] = []
        for part in withoutTags.components(separatedBy: ";") {
            let value = parseEngineComment(part.trimmingCharacters(in: .whitespacesAndNewlines))
            if let eval = value.eval {
                if !matches(eval, #"^(?:[+-]?\d+\.\d{1,2}|[+-]?M\d*)$"#) { return true }
                evals.append(eval)
            }
            if let best = value.bestMove {
                if !matches(best, #"^(?:[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=?[QRBNqrbn])?|O-O(?:-O)?|0-0(?:-0)?|[a-h][1-8][a-h][1-8][qrbn]?)[+#]?[!?]*$"#) { return true }
                bests.append(best)
            }
        }
        if Set(evals).count > 1 || Set(bests).count > 1 { return true }
        if count("[%eval") > 0, let tagged = parsed.eval, evals.contains(where: { $0 != tagged }) { return true }
        return false
    }

    private static func variationDecision(tokens: [PGNToken], offsets: [Int: Int], start: Position)
        -> (order: PGNVariationOrder, uncertain: Bool, nestedMoves: Set<Int>) {
        // Only lines with moves at their own level can change placement.
        var stack: [(index: Int, hasMove: Bool)] = []
        var nested: [Int] = []
        var moveCount = 0
        for (index, token) in tokens.enumerated() {
            switch token {
            case .variationStart:
                if stack.count >= maximumVariationDepth { return (.standard, true, []) }
                stack.append((index, false))
            case .variationEnd:
                if let line = stack.popLast(), line.hasMove, stack.count >= 1 { nested.append(line.index) }
            case .move(let san):
                if !isReportNoise(san) {
                    moveCount += 1
                    if !stack.isEmpty { stack[stack.count - 1].hasMove = true }
                }
            default: break
            }
        }
        // Also account for unclosed lines without making malformed input expensive.
        for (depth, line) in stack.enumerated() where depth >= 1 && line.hasMove { nested.append(line.index) }
        guard !nested.isEmpty else { return (.standard, false, []) }
        guard moveCount <= maximumMoveTreeNodes else { return (.standard, true, Set(nested)) }
        let active = Set(nested)
        struct Frame {
            var position: Position
            var before: Position
            var pending = false
        }
        func replay(old: Bool) -> Bool {
            var frames = [Frame(position: start, before: start)]
            for (index, token) in tokens.enumerated() {
                switch token {
                case .move(let san):
                    let cleaned = MoveAnnotation.extract(from: san).cleaned
                    if isReportNoise(san) { continue }
                    let i = frames.count - 1
                    guard let move = parseMoveWord(cleaned, in: frames[i].position) else { return false }
                    frames[i].before = frames[i].position
                    MoveGenerator.applyMoveUnchecked(&frames[i].position, move)
                    frames[i].pending = false
                case .variationStart:
                    let i = frames.count - 1
                    let useOld = old && frames.count >= 2 && active.contains(index)
                    let position = useOld ? frames[i].position : frames[i].before
                    if useOld { frames[i].pending = true }
                    frames.append(Frame(position: position, before: position))
                case .variationEnd:
                    if frames.count > 1 {
                        if frames.last!.pending { return false }
                        frames.removeLast()
                    }
                default: break
                }
            }
            return !frames.contains(where: { $0.pending })
        }
        let standard = replay(old: false)
        let old = replay(old: true)
        let written = nested.compactMap { offsets[$0] }
        let allZero = !written.isEmpty && written.allSatisfy { $0 == 0 }
        let allOne = !written.isEmpty && written.allSatisfy { $0 == 1 }
        let order: PGNVariationOrder
        var uncertain = false
        if allZero { order = .standard }
        else if allOne { order = old ? .alternativesBeforeContinuation : .standard }
        else if old && !standard { order = .alternativesBeforeContinuation }
        else {
            order = .standard
            uncertain = old && standard
        }
        if written.contains(where: { (order == .standard && $0 == 1) ||
                                     (order == .alternativesBeforeContinuation && $0 == 0) }) {
            uncertain = true
        }
        return (order, uncertain, active)
    }

}

// MARK: - PGN Exporter (Game-tree part)
//
// The token-level `tokenText(from:)` lives in `PGNTokenizer.swift`
// so value-oriented consumers can use it without depending on `Game` or
// `MoveNode`.

extension PGNExporter {

    public static func export(game: Game, tags: PGNGame.OrderedTags? = nil) -> String {
        var lines: [String] = []

        var exportTags = tags ?? defaultTags(for: game)
        // Resolve once for both header and movetext. Rules endings take
        // precedence over contradictory supplied adjudication metadata;
        // off-board endings retain a decided Result when the board is live.
        let result = terminationToken(for: game, tags: exportTags)
        // Supplied sparse tags stay sparse (lossless snapshot contract).
        // Normalize an existing Result rather than fabricating a new header.
        if exportTags["Result"] != nil { exportTags["Result"] = result }

        for key in exportTags.orderedKeys {
            if isValidTagName(key), let value = exportTags[key] {
                lines.append("[\(key) \"\(pgnEscapedTagValue(value))\"]")
            }
        }

        lines.append("")

        // Derive the base ply from the start position so FEN-setup games
        // (including those that begin with black to move at mid-game move
        // numbers) produce correct move indicators like "5... O-O" rather
        // than "1. O-O". Standard-start games produce basePly = 0 and
        // behave identically to before.
        let basePly = startPlyOffset(for: game.startPosition)
        var moveText = String()
        writeNodes(game.rootChildren, basePly: basePly, into: &moveText)
        moveText += result
        lines.append(wrapMoveText(moveText.trimmingCharacters(in: .whitespaces)))

        return lines.joined(separator: "\n")
    }

    private static func isValidTagName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains(where: { $0.isNewline || $0 == "\"" })
    }

    public static func moveText(for rootChildren: [MoveNode]) -> String {
        var result = String()
        writeNodes(rootChildren, basePly: 0, into: &result)
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// Compute the ply offset from a FEN start position so the exporter
    /// generates correct move numbers and white/black indicators.
    ///
    /// For a standard-start game (white to move, fullmoveNumber = 1) this
    /// returns 0 and the exporter behaves identically to before. For a
    /// position where it is black to move at fullmoveNumber N, it returns
    /// (N−1)×2 + 1 so plyIndex 0 maps to "N... <black move>".
    private static func startPlyOffset(for position: Position) -> Int {
        // A FEN can hold any Int here. Past this bound the printed number stops
        // growing, and adding a tree's plies to the offset cannot overflow.
        let base = (min(position.fullmoveNumber, Int.max / 4) - 1) * 2
        return position.activeColor == .white ? base : base + 1
    }

    /// Maximum variation nesting depth `writeLine` will honor. Real
    /// PGN tooling rarely exceeds 10–15 plies of variation nesting;
    /// the cap protects against crafted / corrupted files that nest
    /// variations to depths the call stack can't handle. Past the cap
    /// we emit a balanced sentinel comment and stop descending into
    /// that branch — the rest of the document still exports cleanly.
    fileprivate static let maxVariationDepth = 64

    /// Loops down the main line rather than recursing: a line can be
    /// `maximumMoveTreeNodes` long, and exports run on background threads with
    /// small stacks.
    private static func writeNodes(_ children: [MoveNode], basePly: Int, into result: inout String) {
        var siblings = children
        while let mainNode = siblings.first {
            writeSingleNode(mainNode, basePly: basePly, into: &result, afterVariation: false)

            for variation in siblings.dropFirst() {
                result += "( "
                writeLine(from: variation, basePly: basePly, into: &result, depth: 1)
                result += ") "
            }

            siblings = mainNode.children
        }
    }

    private static func writeLine(from node: MoveNode, basePly: Int, into result: inout String, depth: Int) {
        if depth >= Self.maxVariationDepth {
            result += "{ truncated: variation depth limit } "
            return
        }
        writeSingleNode(node, basePly: basePly, into: &result, afterVariation: false)

        // The move first, then its alternatives: a reader branches a variation
        // from the parent of the move just written.
        var afterVariation = false
        var current = node
        while let next = current.children.first {
            writeSingleNode(next, basePly: basePly, into: &result, afterVariation: afterVariation)
            for variation in current.children.dropFirst() {
                result += "( "
                writeLine(from: variation, basePly: basePly, into: &result, depth: depth + 1)
                result += ") "
            }
            afterVariation = current.children.count > 1
            current = next
        }
    }

    private static func writeSingleNode(_ node: MoveNode, basePly: Int, into result: inout String, afterVariation: Bool) {
        let ply = node.plyIndex + basePly
        let annotationSuffix = node.annotation?.pgnSuffix ?? ""
        let moveNum = ply / 2 + 1
        if ply % 2 == 0 {
            result += "\(moveNum). \(node.notation)\(annotationSuffix) "
        } else {
            let needsMoveNumber = node.parent?.children.first !== node || afterVariation
            if needsMoveNumber {
                result += "\(moveNum)... \(node.notation)\(annotationSuffix) "
            } else {
                result += "\(node.notation)\(annotationSuffix) "
            }
        }

        appendComment(for: node, into: &result)
    }

    private static func appendComment(for node: MoveNode, into result: inout String) {
        let hasEval = node.engineEval != nil
        let hasBest = node.engineBestMoveUCI != nil
        let hasComment = node.comment != nil
        let clockSeconds = node.clockSeconds.flatMap(PGNParser.usableClockSeconds)
        let hasClock = clockSeconds != nil
        guard hasEval || hasBest || hasComment || hasClock else { return }

        var body = ""

        if let seconds = clockSeconds {
            // Use the original seconds-field formatting to retain its rounding
            // at halfway values, then carry its rounded tenths across fields.
            let wholeMinutes = Int(seconds) / 60
            let secondsField = seconds - Double(wholeMinutes * 60)
            let roundedField = Double(String(format: "%.1f", secondsField))!
            let tenths = wholeMinutes * 600 + Int((roundedField * 10).rounded())
            let h = tenths / 36000
            let m = (tenths % 36000) / 600
            let s = (tenths % 600) / 10
            if seconds.truncatingRemainder(dividingBy: 1) > 0 {
                body += String(format: "[%%clk %d:%02d:%02d.%d]", h, m, s, tenths % 10)
            } else {
                body += String(format: "[%%clk %d:%02d:%02d]", h, m, s)
            }
        }

        var needsSeparator = hasClock

        if let eval = node.engineEval {
            if needsSeparator { body += " " }
            // THE SAME COMMAND SYNTAX THE CLOCK ABOVE ALREADY USES. This wrote
            // the evaluation bare — `{[%clk 0:03:00] +0.34}` — so the clock was
            // legible to every tool and the evaluation to none of them: Lichess,
            // ChessBase and python-chess all read `[%eval …]` and nothing else,
            // and `PGNParser.parseEngineComment`'s bare-token branch was the
            // only reader in the world that recovered it.
            //
            // `evalCommandArgument` answers nil only for a mate with no
            // distance (`M` / `-M`), which the command has no spelling for;
            // those keep the bare form rather than being dropped or invented.
            // The reader accepts both spellings, so files exported before today
            // — and every already-stored `moveText` — still parse unchanged.
            if let command = PGNParser.evalCommandArgument(for: eval) {
                body += "[%eval \(command)]"
            } else {
                body += eval
            }
            needsSeparator = true
        }

        if let bestUCI = node.engineBestMoveUCI {
            if needsSeparator { body += "; " }
            let bestSAN = UCIParser.uciToSAN(bestUCI, in: node.positionBefore)
            body += "best \(bestSAN ?? bestUCI)"
            needsSeparator = true
        }

        if let userComment = node.comment {
            if needsSeparator { body += "; " }
            body += userComment
        }

        result += commentText(body) + " "
    }

    /// PGN `Date` formatter, built ONCE. `DateFormatter()` sets up locale +
    /// calendar + ICU — expensive to instantiate (worse on swift-corelibs /
    /// SkipFoundation), and it was rebuilt on every export. Immutable after
    /// configuration and used only for formatting, so sharing is safe.
    private static let pgnDateFormatter: DateFormatter = {
        let f = DateFormatter()
        configurePGNDateFormatter(f)
        return f
    }()

    // Use the device's local date, including timezone changes after startup.
    static func configurePGNDateFormatter(_ formatter: DateFormatter) {
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy.MM.dd"
    }

    static func defaultTags(for game: Game, date: Date = Date()) -> PGNGame.OrderedTags {
        var tags = PGNGame.OrderedTags()
        // Neutral placeholders for a general-purpose kernel; callers that want
        // real metadata pass their own tags to `export(game:tags:)`.
        tags["Event"] = "Casual Game"
        tags["Site"] = "?"

        tags["Date"] = Self.pgnDateFormatter.string(from: date)

        tags["Round"] = "-"
        tags["White"] = "Player 1"
        tags["Black"] = "Player 2"
        tags["Result"] = resultString(for: game)
        if game.startPosition != .initial() {
            tags["SetUp"] = "1"
            tags["FEN"] = game.startPosition.fen
        }
        return tags
    }

    /// The movetext's closing token, which PGN requires to equal the Result
    /// tag.
    ///
    /// The board decides when it can — mate and the automatic draws. When it
    /// cannot, because the game ended off the board (a resignation, a flag,
    /// an agreed draw — `GameState` has no case for any of them), a decided
    /// Result tag is the answer. This used to write `*` for those, so a
    /// resigned game exported `[Result "1-0"]` over movetext ending `*`, and a
    /// reader that trusts the token read the game back as unfinished.
    static func terminationToken(for game: Game, tags: PGNGame.OrderedTags) -> String {
        let fromBoard = resultString(for: game)
        if fromBoard != "*" { return fromBoard }
        if let tagged = tags["Result"], PGNGame.decidedResults.contains(tagged) { return tagged }
        return "*"
    }

    private static func resultString(for game: Game) -> String {
        switch game.gameState {
        case .checkmate:
            return game.position.activeColor == .white ? "0-1" : "1-0"
        case .stalemate, .draw, .insufficientMaterial, .repetition:
            return "1/2-1/2"
        default:
            return "*"
        }
    }

    private static func wrapMoveText(_ text: String, lineLength: Int = 80) -> String {
        var lines: [String] = []
        var currentLine = ""

        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            // Wrapping a semicolon comment would turn its continuation into
            // moves. commentText always puts these comments on their own line.
            if line.hasPrefix(";") {
                lines.append(String(line))
                continue
            }
            for word in line.split(separator: " ") {
                if currentLine.isEmpty {
                    currentLine = String(word)
                } else if currentLine.count + 1 + word.count > lineLength {
                    lines.append(currentLine)
                    currentLine = String(word)
                } else {
                    currentLine += " " + word
                }
            }
            if !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = ""
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
