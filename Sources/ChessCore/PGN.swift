import Foundation

// `PGNParser` is split across two files. The pure tokenization /
// snapshot path lives in `PGNTokenizer.swift` (used by stats compute,
// the tactics extractor, the personal-book build, and the perf-harness
// CLI). This file carries the `Game`-bound entry points (`loadGame`)
// and the exporter — anything that materialises or walks the live
// `MoveNode` tree.

extension PGNParser {

    public static func loadGame(from pgn: String) -> Game? {
        let pgnGames = parse(pgn)
        guard let pgnGame = pgnGames.first else { return nil }
        return loadGame(from: pgnGame)
    }

    public static func loadGame(from pgnGame: PGNGame) -> Game? {
        let game = Game()

        // Honour SetUp/FEN: if the PGN specifies a non-initial start position,
        // seed the game from that FEN before building the move tree so every
        // SAN is parsed relative to the real starting board. For standard-start
        // games (no FEN tag) this branch is skipped — behaviour is identical to
        // before. Returns nil if the FEN is syntactically invalid.
        if let fen = pgnGame.tags["FEN"], !fen.isEmpty {
            guard game.loadFEN(fen) else { return nil }
        }

        if pgnGame.moveTokens.isEmpty {
            for san in pgnGame.moves {
                guard let move = parseMove(san, in: game.position) else {
                    return game
                }
                game.applyMoveFromPGN(move)
            }
        } else {
            buildTree(game: game, tokens: pgnGame.moveTokens)
        }

        return game
    }

    private static func buildTree(game: Game, tokens: [PGNToken]) {
        var nodeStack: [MoveNode?] = [nil]

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
                guard let move = parseMove(cleanedSan, in: currentPos) else { continue }

                let parentNode = nodeStack.last ?? nil
                let siblings = parentNode?.children ?? game.rootChildren
                let ply = (parentNode?.plyIndex ?? -1) + 1

                if let existing = siblings.first(where: { $0.move == move }) {
                    if let annotation { existing.annotation = annotation }
                    nodeStack[nodeStack.count - 1] = existing
                } else {
                    let notation = MoveGenerator.algebraicNotation(for: move, in: currentPos)
                    let newNode = MoveNode(move: move, notation: notation, positionBefore: currentPos, parent: parentNode, plyIndex: ply, annotation: annotation)
                    if let parent = parentNode {
                        parent.children.append(newNode)
                    } else {
                        game.rootChildren.append(newNode)
                    }
                    nodeStack[nodeStack.count - 1] = newNode
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
// so SwiftData-only code paths (`Models/StoredGame.swift`'s encoders)
// can reach it without depending on `Game` / `MoveNode`.
// (V1-REVIEW follow-up 2026-06-10 §3 rec #25: stale Item.swift /
// perf-harness references corrected)

extension PGNExporter {

    public static func export(game: Game, tags: PGNGame.OrderedTags? = nil) -> String {
        var lines: [String] = []

        let exportTags = tags ?? defaultTags(for: game)

        for key in exportTags.orderedKeys {
            if let value = exportTags[key] {
                lines.append("[\(key) \"\(value)\"]")
            }
        }

        lines.append("")

        var moveText = String()
        writeNodes(game.rootChildren, startPly: 0, into: &moveText)
        moveText += resultString(for: game)
        lines.append(wrapMoveText(moveText.trimmingCharacters(in: .whitespaces)))

        return lines.joined(separator: "\n")
    }

    public static func moveText(for rootChildren: [MoveNode]) -> String {
        var result = String()
        writeNodes(rootChildren, startPly: 0, into: &result)
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// Maximum variation nesting depth `writeLine` will honour. Real
    /// PGN tooling rarely exceeds 10–15 plies of variation nesting;
    /// the cap protects against crafted / corrupted files that nest
    /// variations to depths the call stack can't handle. Past the cap
    /// we emit a balanced sentinel comment and stop descending into
    /// that branch — the rest of the document still exports cleanly.
    /// (V1-REVIEW 2026-06-09 §3, medium)
    private static let maxVariationDepth = 64

    private static func writeNodes(_ children: [MoveNode], startPly: Int, into result: inout String) {
        guard let mainNode = children.first else { return }

        writeSingleNode(mainNode, into: &result, afterVariation: false)

        for variation in children.dropFirst() {
            result += "( "
            writeLine(from: variation, into: &result, depth: 1)
            result += ") "
        }

        if !mainNode.children.isEmpty {
            writeNodes(mainNode.children, startPly: mainNode.plyIndex + 1, into: &result)
        }
    }

    private static func writeLine(from node: MoveNode, into result: inout String, depth: Int) {
        if depth >= Self.maxVariationDepth {
            result += "{ truncated: variation depth limit } "
            return
        }
        writeSingleNode(node, into: &result, afterVariation: false)

        var current = node
        while let next = current.children.first {
            let hasVariations = current.children.count > 1
            for variation in current.children.dropFirst() {
                result += "( "
                writeLine(from: variation, into: &result, depth: depth + 1)
                result += ") "
            }
            writeSingleNode(next, into: &result, afterVariation: hasVariations)
            current = next
        }
    }

    private static func writeSingleNode(_ node: MoveNode, into result: inout String, afterVariation: Bool) {
        let ply = node.plyIndex
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

    private static func defaultTags(for game: Game) -> PGNGame.OrderedTags {
        var tags = PGNGame.OrderedTags()
        tags["Event"] = "Casual Game"
        tags["Site"] = "Fianchetto App"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        tags["Date"] = formatter.string(from: Date())

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
