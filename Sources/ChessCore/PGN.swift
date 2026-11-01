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

/// Information a storage caller needs before replacing the original movetext.
/// Callers building `PGNGame` by hand must carry over move-text diagnostics.
public struct PGNLenientLoadReport {
    public let game: Game
    public let imputedMoves: [PGNImputedMove]
    public let droppedMoveTokens: [String]
    public let hasUnterminatedBraceComment: Bool
    /// Whether the loaded main line differs from a replay of depth-zero tokens.
    public let mainLineDiffersFromSnapshot: Bool
    public let exceedsExportVariationDepth: Bool
    public let hasUnrecognizedSetupTag: Bool
    public let hasInconsistentMoveNumbers: Bool

    /// Whether moves and the start position can safely replace stored text.
    /// This does not cover comments or NAGs the exporter cannot carry.
    /// Tags with names on one line and no double quote are preserved by the exporter.
    /// For a stored movetext row, use `tokenizeWithDiagnostics`, not `parse(text).first`:
    /// parsing may split at a bracket-only line or skip an oversized record.
    public var canReplaceStoredText: Bool {
        droppedMoveTokens.isEmpty && !hasUnterminatedBraceComment && !mainLineDiffersFromSnapshot
            && !exceedsExportVariationDepth && !hasUnrecognizedSetupTag && !hasInconsistentMoveNumbers && imputedMoves.isEmpty
    }
}

private final class PGNLoadAccounting {
    var dropped: [String] = []
}

extension PGNParser {

    /// Maximum number of `MoveNode` objects materialized for one PGN game,
    /// including variations. This is deliberately far above practical game
    /// trees while bounding adversarial, compact repetition input.
    public static let maximumMoveTreeNodes = 65_536

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
        return PGNLenientLoadReport(game: game, imputedMoves: [], droppedMoveTokens: accounting.dropped,
            hasUnterminatedBraceComment: pgnGame.diagnostics.contains(.unterminatedBraceComment),
            mainLineDiffersFromSnapshot: mainLineDiffers(pgnGame, game: game),
            exceedsExportVariationDepth: exceedsExportDepth(game),
            hasUnrecognizedSetupTag: pgnGame.tags.orderedKeys.contains { $0 != "FEN" && $0.uppercased() == "FEN" },
            hasInconsistentMoveNumbers: pgnGame.hasInconsistentMoveNumbers)
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
            if let move = parseMove(san, in: position, legalMoves: legal) {
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
                          let move = parseMove(next, in: trial) else { return false }
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
        return PGNLenientLoadReport(game: report.game, imputedMoves: imputed,
            droppedMoveTokens: report.droppedMoveTokens,
            hasUnterminatedBraceComment: report.hasUnterminatedBraceComment,
            mainLineDiffersFromSnapshot: report.mainLineDiffersFromSnapshot,
            exceedsExportVariationDepth: report.exceedsExportVariationDepth,
            hasUnrecognizedSetupTag: report.hasUnrecognizedSetupTag,
            hasInconsistentMoveNumbers: report.hasInconsistentMoveNumbers)
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
    static func isReportNoise(_ san: String) -> Bool {
        let cleaned = MoveAnnotation.extract(from: san).cleaned
        return isMoveTextNoise(cleaned) || (!cleaned.isEmpty && cleaned.allSatisfy { $0.isASCII && $0.isNumber })
            || cleaned == "1/2" || cleaned == "½-½"
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
                guard let move = parseMove(san, in: position) else { return true }
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
                guard let move = parseMove(san, in: game.position) else {
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
                game.applyMoveFromPGN(move)
                materializedNodeCount += 1
            }
        } else {
            try buildTree(
                game: game,
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
        tokens: [PGNToken],
        maximumNodes: Int,
        rejectsUnparseableMainLine: Bool,
        accounting: PGNLoadAccounting?
    ) throws {
        var nodeStack: [MoveNode?] = [nil]
        // Parallel to `nodeStack`: the frame's next move continues a line whose
        // alternatives were read first (see `opensAfterLastMove`).
        var continuationIsPending = [false]
        let nestedLines = nestedVariationMoves(in: tokens)
        var materializedNodeCount = 0
        // Open parentheses in the variation being abandoned, its own included.
        // Its own close still reaches the switch, to pop its frame.
        var abandonedDepth = 0

        for (tokenIndex, token) in tokens.enumerated() {
            if abandonedDepth > 0 {
                if case .move(let san) = token, !isReportNoise(san) {
                    accounting?.dropped.append(san)
                }
                if case .variationStart = token { abandonedDepth += 1 }
                if case .variationEnd = token { abandonedDepth -= 1 }
                if abandonedDepth > 0 { continue }
            }
            switch token {
            case .move(let san):
                let (cleanedSan, annotation) = MoveAnnotation.extract(from: san)
                if isMoveTextNoise(cleanedSan) { continue }
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

                if let existing = siblings.first(where: { $0.move == move }) {
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
                    if let parent = parentNode {
                        parent.children.append(newNode)
                    } else {
                        game.rootChildren.append(newNode)
                    }
                    nodeStack[nodeStack.count - 1] = newNode
                    materializedNodeCount += 1
                }

            case .nag(let number):
                if let annotation = MoveAnnotation.from(nag: number),
                   let last = nodeStack.last, let currentNode = last {
                    currentNode.annotation = annotation
                }

            case .variationStart:
                let currentNode = nodeStack.last ?? nil
                let branchPoint = currentNode?.parent
                // A line over the budget fails either way, and replaying it
                // would spend work the budget exists to bound.
                if let currentNode, let line = nestedLines[tokenIndex],
                   line.count <= maximumNodes - materializedNodeCount,
                   opensAfterLastMove(line, lastMove: currentNode, startPosition: game.startPosition) {
                    continuationIsPending[continuationIsPending.count - 1] = true
                    nodeStack.append(currentNode)
                } else {
                    nodeStack.append(branchPoint)
                }
                continuationIsPending.append(false)

            case .variationEnd:
                if nodeStack.count > 1 {
                    nodeStack.removeLast()
                    continuationIsPending.removeLast()
                }

            case .comment(let text):
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

    /// The moves each nested variation plays at its own level, keyed by the
    /// index of its opening token. One pass, so hostile nesting stays linear.
    private static func nestedVariationMoves(in tokens: [PGNToken]) -> [Int: [String]] {
        var moves: [Int: [String]] = [:]
        var openVariations: [Int] = []
        for (index, token) in tokens.enumerated() {
            switch token {
            case .variationStart:
                openVariations.append(index)
                if openVariations.count >= 2 { moves[index] = [] }
            case .variationEnd:
                _ = openVariations.popLast()
            case .move(let san):
                if openVariations.count >= 2, let open = openVariations.last {
                    moves[open, default: []].append(san)
                }
            case .comment, .nag:
                break
            }
        }
        return moves
    }

    /// Whether a nested variation was stored by an exporter that wrote a line's
    /// alternatives ahead of the move they replace, so it starts from the
    /// position after `lastMove` rather than from `lastMove`'s parent. Library
    /// rows keep only this text, and those variations are recoverable from it.
    ///
    /// Move numbers do not survive tokenizing, and SAN carries no colour, so the
    /// whole line has to replay. Standard PGN wins whenever it replays, which
    /// leaves a stored line that is legal from both positions in standard place.
    private static func opensAfterLastMove(
        _ line: [String],
        lastMove: MoveNode,
        startPosition: Position
    ) -> Bool {
        let standardStart = lastMove.parent?.positionAfter ?? startPosition
        return !replays(line, from: standardStart) && replays(line, from: lastMove.positionAfter)
    }

    private static func replays(_ line: [String], from start: Position) -> Bool {
        var position = start
        for san in line {
            let (cleanedSan, _) = MoveAnnotation.extract(from: san)
            if isMoveTextNoise(cleanedSan) { continue }
            guard let move = parseMove(cleanedSan, in: position) else { return false }
            MoveGenerator.applyMoveUnchecked(&position, move)
        }
        return !line.isEmpty
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
            let totalInt = Int(seconds)
            let h = totalInt / 3600
            let m = (totalInt % 3600) / 60
            let fractional = seconds.truncatingRemainder(dividingBy: 1)
            if fractional > 0 {
                let s = seconds - Double(h * 3600 + m * 60)
                body += String(format: "[%%clk %d:%02d:%04.1f]", h, m, s)
            } else {
                let s = totalInt % 60
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
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    private static func defaultTags(for game: Game) -> PGNGame.OrderedTags {
        var tags = PGNGame.OrderedTags()
        // Neutral placeholders for a general-purpose kernel; callers that want
        // real metadata pass their own tags to `export(game:tags:)`.
        tags["Event"] = "Casual Game"
        tags["Site"] = "?"

        tags["Date"] = Self.pgnDateFormatter.string(from: Date())

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
