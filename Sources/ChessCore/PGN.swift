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

    private static func materialize(
        _ pgnGame: PGNGame,
        maximumTreeNodes: Int,
        rejectsUnparseableMainLine: Bool
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
                if isMoveTextNoise(MoveAnnotation.extract(from: san).cleaned) { continue }
                guard let move = parseMove(san, in: game.position) else {
                    if rejectsUnparseableMainLine {
                        throw PGNDiagnostic.unparseableMainlineMove(
                            san: MoveAnnotation.extract(from: san).cleaned,
                            plyIndex: materializedNodeCount
                        )
                    }
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
                rejectsUnparseableMainLine: rejectsUnparseableMainLine
            )
        }

        return game
    }

    private static func buildTree(
        game: Game,
        tokens: [PGNToken],
        maximumNodes: Int,
        rejectsUnparseableMainLine: Bool
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
        moveText += result
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
    private static let maxVariationDepth = 64

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
