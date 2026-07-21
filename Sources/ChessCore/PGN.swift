import Foundation

// `PGNParser` is split across two files. The pure tokenization /
// snapshot path lives in `PGNTokenizer.swift` for consumers that do not need
// to materialize a live tree. This file carries the `Game`-bound entry points (`loadGame`)
// and the exporter — anything that materialises or walks the live
// `MoveNode` tree.

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

    public static func loadGame(from pgnGame: PGNGame) -> Game? {
        try? loadGame(
            from: pgnGame,
            maximumTreeNodes: maximumMoveTreeNodes
        )
    }

    /// Materialize one parsed PGN with an explicit whole-tree resource budget.
    ///
    /// Unlike the compatibility overload, this surface reports a limit breach
    /// as ``PGNDiagnostic/moveTreeNodeLimitExceeded(maximumNodes:)``. No partial
    /// game escapes: the local tree is released as the error unwinds.
    public static func loadGame(
        from pgnGame: PGNGame,
        maximumTreeNodes: Int
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
            for san in pgnGame.moves {
                guard let move = parseMove(san, in: game.position) else {
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
                maximumNodes: maximumTreeNodes
            )
        }

        return game
    }

    private static func buildTree(
        game: Game,
        tokens: [PGNToken],
        maximumNodes: Int
    ) throws {
        var nodeStack: [MoveNode?] = [nil]
        var materializedNodeCount = 0

        for token in tokens {
            switch token {
            case .move(let san):
                let (cleanedSan, annotation) = MoveAnnotation.extract(from: san)
                let currentPos: Position
                if let last = nodeStack.last, let node = last {
                    currentPos = node.positionAfter
                } else {
                    currentPos = game.startPosition
                }
                // Generate the legal-move list ONCE and thread it into both the
                // SAN parse and the canonical-notation derivation.
                let legal = MoveGenerator.legalMoves(for: currentPos)
                guard let move = parseMove(cleanedSan, in: currentPos, legalMoves: legal) else { continue }

                let parentNode = nodeStack.last ?? nil
                let siblings = parentNode?.children ?? game.rootChildren
                let ply = (parentNode?.plyIndex ?? -1) + 1

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
                nodeStack.append(branchPoint)

            case .variationEnd:
                if nodeStack.count > 1 {
                    nodeStack.removeLast()
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
}

// MARK: - PGN Exporter (Game-tree part)
//
// The token-level `tokenText(from:)` lives in `PGNTokenizer.swift`
// so value-oriented consumers can use it without depending on `Game` or
// `MoveNode`.

extension PGNExporter {

    public static func export(game: Game, tags: PGNGame.OrderedTags? = nil) -> String {
        var lines: [String] = []

        let exportTags = tags ?? defaultTags(for: game)

        for key in exportTags.orderedKeys {
            if let value = exportTags[key] {
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
        moveText += resultString(for: game)
        lines.append(wrapMoveText(moveText.trimmingCharacters(in: .whitespaces)))

        return lines.joined(separator: "\n")
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
        let base = (position.fullmoveNumber - 1) * 2
        return position.activeColor == .white ? base : base + 1
    }

    /// Maximum variation nesting depth `writeLine` will honor. Real
    /// PGN tooling rarely exceeds 10–15 plies of variation nesting;
    /// the cap protects against crafted / corrupted files that nest
    /// variations to depths the call stack can't handle. Past the cap
    /// we emit a balanced sentinel comment and stop descending into
    /// that branch — the rest of the document still exports cleanly.
    private static let maxVariationDepth = 64

    private static func writeNodes(_ children: [MoveNode], basePly: Int, into result: inout String) {
        guard let mainNode = children.first else { return }

        writeSingleNode(mainNode, basePly: basePly, into: &result, afterVariation: false)

        for variation in children.dropFirst() {
            result += "( "
            writeLine(from: variation, basePly: basePly, into: &result, depth: 1)
            result += ") "
        }

        if !mainNode.children.isEmpty {
            writeNodes(mainNode.children, basePly: basePly, into: &result)
        }
    }

    private static func writeLine(from node: MoveNode, basePly: Int, into result: inout String, depth: Int) {
        if depth >= Self.maxVariationDepth {
            result += "{ truncated: variation depth limit } "
            return
        }
        writeSingleNode(node, basePly: basePly, into: &result, afterVariation: false)

        var current = node
        while let next = current.children.first {
            let hasVariations = current.children.count > 1
            for variation in current.children.dropFirst() {
                result += "( "
                writeLine(from: variation, basePly: basePly, into: &result, depth: depth + 1)
                result += ") "
            }
            writeSingleNode(next, basePly: basePly, into: &result, afterVariation: hasVariations)
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
        let hasClock = node.clockSeconds != nil
        guard hasEval || hasBest || hasComment || hasClock else { return }

        result += "{"

        if let seconds = node.clockSeconds {
            let totalInt = Int(seconds)
            let h = totalInt / 3600
            let m = (totalInt % 3600) / 60
            let fractional = seconds.truncatingRemainder(dividingBy: 1)
            if fractional > 0 {
                let s = seconds - Double(h * 3600 + m * 60)
                result += String(format: "[%%clk %d:%02d:%04.1f]", h, m, s)
            } else {
                let s = totalInt % 60
                result += String(format: "[%%clk %d:%02d:%02d]", h, m, s)
            }
        }

        var needsSeparator = node.clockSeconds != nil

        if let eval = node.engineEval {
            if needsSeparator { result += " " }
            result += eval
            needsSeparator = true
        }

        if let bestUCI = node.engineBestMoveUCI {
            if needsSeparator { result += "; " }
            let bestSAN = UCIParser.uciToSAN(bestUCI, in: node.positionBefore)
            result += "best \(bestSAN ?? bestUCI)"
            needsSeparator = true
        }

        if let userComment = node.comment {
            if needsSeparator { result += "; " }
            // PGN has no escape for '}' — a bare '}' inside a comment
            // block terminates the block early. Replace with ')' per
            // convention (the PGN spec does not provide an escape
            // sequence for this character).
            result += userComment.replacingOccurrences(of: "}", with: ")")
        }

        result += "} "
    }

    /// PGN string-token escaping (§8.1 of the PGN spec): backslash must be
    /// escaped before quote so a single backslash in the input doesn't
    /// accidentally escape the following character. Without this, a quote or
    /// backslash in a tag value emitted out-of-spec PGN whose header string
    /// terminates early in conforming readers (SCID, python-chess, Lichess).
    private static func pgnEscapedTagValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
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
        return tags
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

        for word in text.split(separator: " ") {
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
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
