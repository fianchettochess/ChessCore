import Foundation

/// Structured issues discovered while parsing or materializing PGN input.
///
/// Lenient warnings can travel on parsed values; failures that cannot safely
/// produce a value also conform to `Error` for throwing APIs.
public nonisolated enum PGNDiagnostic: Error, Equatable, Sendable {
    /// A tag roster was present but the record contained no movetext at all.
    case tagsOnlyRecord
    /// A supplied FEN tag could not be parsed, so no moves were interpreted.
    case invalidFEN(String)
    /// A main-line SAN token could not be applied at the expected ply.
    case unparseableMainlineMove(san: String, plyIndex: Int)
    /// Materializing the complete move tree would exceed its resource budget.
    case moveTreeNodeLimitExceeded(maximumNodes: Int)
}

// MARK: - PGN Game model

public nonisolated struct PGNGame: Identifiable, Sendable {
    public let id = UUID()
    public var tags: OrderedTags = OrderedTags()
    public var moves: [String] = []
    public var result: String? = nil
    public var moveTokens: [PGNToken] = []
    public var diagnostics: [PGNDiagnostic] = []

    public nonisolated init() {}

    public nonisolated var white: String { tags["White"] ?? "?" }
    public nonisolated var black: String { tags["Black"] ?? "?" }
    public nonisolated var date: String { tags["Date"] ?? "?" }
    public nonisolated var event: String { tags["Event"] ?? "" }
    public nonisolated var resultText: String { result ?? tags["Result"] ?? "*" }
    public nonisolated var opening: String { tags["Opening"] ?? tags["ECO"] ?? "" }
    public nonisolated var moveCount: Int { (moves.count + 1) / 2 }

    // Equatable is synthesized over (keys, values) — key ORDER participates in
    // equality, which is what tag-mirror change detection wants: any edit,
    // including a pure reorder, reads as "changed". (Game-wrap Stage 2 prep)
    public struct OrderedTags: Sendable, Equatable {
        private var keys: [String] = []
        private var values: [String: String] = [:]

        public nonisolated init() {}

        public nonisolated static let sevenTagRoster = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]

        public nonisolated subscript(key: String) -> String? {
            get { values[key] }
            set {
                if let newValue {
                    if values[key] == nil { keys.append(key) }
                    values[key] = newValue
                } else {
                    keys.removeAll { $0 == key }
                    values[key] = nil
                }
            }
        }

        public nonisolated var orderedKeys: [String] {
            let roster = Self.sevenTagRoster.filter { values[$0] != nil }
            let rest = keys.filter { !Self.sevenTagRoster.contains($0) }
            return roster + rest
        }

        /// Raw insertion order used by lossless model snapshots. PGN export
        /// intentionally continues to use `orderedKeys`, which projects the
        /// canonical Seven Tag Roster ahead of supplemental tags.
        nonisolated var insertionOrderedKeys: [String] { keys }

        public nonisolated var isEmpty: Bool { keys.isEmpty }
    }
}

// MARK: - PGN Tokens

public nonisolated enum PGNToken: Sendable {
    case move(String)
    case variationStart
    case variationEnd
    case comment(String)
    case nag(Int)
}

// MARK: - Sendable game-tree snapshots

/// A `Sendable` representation of a parsed PGN mainline. Carries everything
/// downstream consumers (tactics extractor, library import, personal-book
/// build, etc.) actually need, without the main-actor-bound `Game` /
/// `MoveNode` class graph. Build this from a `Task.detached` on PGN text;
/// hop back to main only if you need to construct a live `Game` from it.
public nonisolated struct MainLineMoveSnapshot: Sendable {
    public let move: Move
    public let notation: String
    public let positionBefore: Position
    public let positionAfter: Position
    public let annotation: MoveAnnotation?
    public let comment: String?
    public let engineEval: String?
    public let engineBestMoveUCI: String?
    public let clockSeconds: TimeInterval?
}

public nonisolated struct ParsedMainLine: Sendable {
    public let startPosition: Position
    public let moves: [MainLineMoveSnapshot]
    public let diagnostics: [PGNDiagnostic]
}

// MARK: - PGN Parser (tokenize / parse / snapshot)
//
// `PGNParser` is split across two files. This one carries the pure
// tokenization and `Sendable`-snapshot path — used by anything that
// works off a PGN string but doesn't need to materialise a live `Game`
// tree (stats compute, tactics extractor, personal-book build, the
// perf-harness CLI). The companion file `PGN.swift` keeps the
// `Game`-bound `loadGame` overloads and the exporter.

public enum PGNParser {

    public nonisolated static func parse(_ pgn: String) -> [PGNGame] {
        parse(pgn, maximumMoveTextBytes: 8 * 1024 * 1024)
    }

    /// Internal limit seam keeps oversized-input behavior directly testable
    /// without allocating multi-megabyte fixtures in the package test suite.
    nonisolated static func parse(
        _ pgn: String,
        maximumMoveTextBytes: Int
    ) -> [PGNGame] {
        precondition(maximumMoveTextBytes > 0)
        var games: [PGNGame] = []
        var current = PGNGame()
        var moveTextLines: [String] = []
        var moveTextByteCount = 0

        // Defensive upper bound on a single game's move-text accumulation.
        // No real PGN reaches anywhere near 8 MB of moves (a 1000-move game is
        // a few KB). Accumulate lines and join once so a near-limit game stays
        // linear rather than repeatedly copying/recounting a growing String.
        // An overflowed game is discarded whole; returning its truncated prefix
        // would manufacture a valid-looking but incomplete game.
        var moveTextOverflow = false

        for line in pgn.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if !moveTextLines.isEmpty || moveTextOverflow {
                    if !moveTextOverflow {
                        let moveText = moveTextLines.joined(separator: " ")
                        let tokens = tokenize(moveText)
                        current.moves = flatMoves(from: tokens)
                        current.moveTokens = tokens
                        current.result = extractResult(from: moveText)
                        games.append(current)
                    }
                    current = PGNGame()
                    moveTextLines.removeAll(keepingCapacity: true)
                    moveTextByteCount = 0
                    moveTextOverflow = false
                }
                if let (key, value) = parseTag(trimmed) {
                    current.tags[key] = value
                }
            } else if trimmed.isEmpty {
                continue
            } else {
                // A non-empty, non-tag line ends the tag section even without
                // the spec's blank separator line — hand-edited / concatenated
                // PGNs often omit it. Previously such movetext was silently
                // dropped (tags-only games) and consecutive games merged.
                if moveTextOverflow { continue }
                let separatorBytes = moveTextLines.isEmpty ? 0 : 1
                let nextLineBytes = trimmed.utf8.count
                if moveTextByteCount + separatorBytes + nextLineBytes > maximumMoveTextBytes {
                    moveTextOverflow = true
                    moveTextLines.removeAll(keepingCapacity: false)
                    moveTextByteCount = 0
                    continue
                }
                moveTextLines.append(trimmed)
                moveTextByteCount += separatorBytes + nextLineBytes
            }
        }

        if !moveTextOverflow && (!moveTextLines.isEmpty || !current.tags.isEmpty) {
            if moveTextLines.isEmpty && !current.tags.isEmpty {
                current.diagnostics.append(.tagsOnlyRecord)
            }
            let moveText = moveTextLines.joined(separator: " ")
            let tokens = tokenize(moveText)
            current.moves = flatMoves(from: tokens)
            current.moveTokens = tokens
            current.result = extractResult(from: moveText)
            games.append(current)
        }

        return games
    }

    public nonisolated static func tokenize(_ moveText: String) -> [PGNToken] {
        var tokens: [PGNToken] = []
        var i = moveText.startIndex

        while i < moveText.endIndex {
            let ch = moveText[i]

            if ch == "(" {
                tokens.append(.variationStart)
                i = moveText.index(after: i)
            } else if ch == ")" {
                tokens.append(.variationEnd)
                i = moveText.index(after: i)
            } else if ch == "{" {
                let start = moveText.index(after: i)
                if let end = moveText[start...].firstIndex(of: "}") {
                    let comment = String(moveText[start..<end])
                    tokens.append(.comment(comment))
                    i = moveText.index(after: end)
                } else {
                    i = moveText.endIndex
                }
            } else if ch.isWhitespace {
                i = moveText.index(after: i)
            } else {
                let start = i
                while i < moveText.endIndex && !moveText[i].isWhitespace
                    && moveText[i] != "(" && moveText[i] != ")" && moveText[i] != "{" {
                    i = moveText.index(after: i)
                }
                let word = String(moveText[start..<i])
                if word.hasPrefix("$"), let nagNumber = Int(word.dropFirst()) {
                    tokens.append(.nag(nagNumber))
                } else if !isResult(word) {
                    let stripped = stripMoveNumberPrefix(word)
                    if !stripped.isEmpty {
                        tokens.append(.move(stripped))
                    }
                }
            }
        }

        return tokens
    }

    public nonisolated static func flatMoves(from tokens: [PGNToken]) -> [String] {
        var moves: [String] = []
        var depth = 0
        for token in tokens {
            switch token {
            case .variationStart: depth += 1
            case .variationEnd: depth = max(0, depth - 1)
            case .move(let san) where depth == 0: moves.append(san)
            default: break
            }
        }
        return moves
    }

    public nonisolated static func parseMove(_ san: String, in position: Position) -> Move? {
        let cleaned = String(san.filter { $0 != "+" && $0 != "#" && $0 != "!" && $0 != "?" })
            .trimmingCharacters(in: .whitespaces)

        if cleaned == "O-O" || cleaned == "0-0" {
            let rank = position.activeColor == .white ? 0 : 7
            return MoveGenerator.findLegalMoves(for: position, piece: .king, to: Square(file: 6, rank: rank))
                .first { $0.isCastling }
        }
        if cleaned == "O-O-O" || cleaned == "0-0-0" {
            let rank = position.activeColor == .white ? 0 : 7
            return MoveGenerator.findLegalMoves(for: position, piece: .king, to: Square(file: 2, rank: rank))
                .first { $0.isCastling }
        }

        var remaining = cleaned
        var promotion: PieceType? = nil
        var pieceType: PieceType = .pawn
        var disambigFile: Int? = nil
        var disambigRank: Int? = nil

        if let eqIdx = remaining.firstIndex(of: "=") {
            let afterEq = remaining.index(after: eqIdx)
            guard afterEq < remaining.endIndex else {
                // Truncated promotion like "e8=": no piece letter after the
                // equals sign. Reject the move rather than crash on the
                // out-of-bounds subscript.
                return nil
            }
            promotion = pieceTypeFromChar(remaining[afterEq])
            remaining = String(remaining[remaining.startIndex..<eqIdx])
        }

        guard let firstChar = remaining.first else { return nil }
        if firstChar.isUppercase {
            pieceType = pieceTypeFromChar(firstChar) ?? .pawn
            remaining = String(remaining.dropFirst())
        }

        remaining = remaining.replacingOccurrences(of: "x", with: "")

        guard remaining.count >= 2 else { return nil }

        let targetAlgebraic = String(remaining.suffix(2))
        let disambig = String(remaining.dropLast(2))

        guard let target = Square(algebraic: targetAlgebraic) else { return nil }

        for char in disambig {
            if char >= "a" && char <= "h", let ascii = char.asciiValue {
                disambigFile = Int(ascii) - 97
            } else if char >= "1" && char <= "8", let ascii = char.asciiValue {
                disambigRank = Int(ascii) - 49
            }
        }

        let candidates = MoveGenerator.findLegalMoves(for: position, piece: pieceType, to: target)
            .filter { move in
                // A promotion piece is part of SAN, not an optional hint. An
                // omitted suffix must not silently select the queen from the
                // otherwise-identical legal promotion moves.
                guard move.promotion == promotion else { return false }

                if let df = disambigFile {
                    guard move.from.file == df else { return false }
                }
                if let dr = disambigRank {
                    guard move.from.rank == dr else { return false }
                }

                return true
            }

        if candidates.count == 1 {
            return candidates[0]
        }

        // Under-specified SAN is not deterministic. Choosing generator order
        // here would make a malformed PGN describe a different game.
        return nil
    }

    /// Build a `Sendable` mainline snapshot from a parsed PGN game. Variations
    /// and tags are dropped; everything else (positions, comments, engine
    /// metadata, annotations) is carried over. This is the off-main entrypoint
    /// for consumers that previously had to construct a full `Game` just to
    /// walk the mainline.
    /// Tokenize raw move text and parse its main-line snapshot in one
    /// step — the `PGNGame() + tokenize + parseMainLineSnapshot` prelude
    /// the tactics / endgame / stats extractors each repeated verbatim.
    /// The per-caller minimum-move-count guard stays at the call site.
    /// Pass `pliesLimit` to stop collecting moves after N plies (useful
    /// for opening-prefix-only consumers — avoids paying the full
    /// parse cost for long games). Defaults to `Int.max` so existing
    /// callers see identical behaviour. (bounded-perf 2026-07-01)
    /// (dedup 2026-06-17)
    /// Resolve the starting position shared by snapshot and live-tree PGN
    /// materialization. `nil` means a non-empty FEN tag was invalid.
    nonisolated static func startingPosition(for pgnGame: PGNGame) -> Position? {
        guard let fen = pgnGame.tags["FEN"], !fen.isEmpty else {
            return Position.initial()
        }
        return Position(fen: fen)
    }

    public nonisolated static func mainLineSnapshot(
        fromMoveText moveText: String,
        pliesLimit: Int = Int.max
    ) -> ParsedMainLine {
        var pgnGame = PGNGame()
        pgnGame.moveTokens = tokenize(moveText)
        return parseMainLineSnapshot(from: pgnGame, pliesLimit: pliesLimit)
    }

    public nonisolated static func parseMainLineSnapshot(
        from pgnGame: PGNGame,
        pliesLimit: Int = Int.max
    ) -> ParsedMainLine {
        // Invalid setup input fails closed. Falling back to the initial board
        // would make unrelated SAN appear valid and manufacture a line.
        guard let startPosition = startingPosition(for: pgnGame) else {
            let fen = pgnGame.tags["FEN"] ?? ""
            return ParsedMainLine(
                startPosition: .initial(),
                moves: [],
                diagnostics: pgnGame.diagnostics + [.invalidFEN(fen)]
            )
        }
        var position = startPosition
        var moves: [MainLineMoveSnapshot] = []

        let tokens: [PGNToken] = pgnGame.moveTokens.isEmpty
            ? pgnGame.moves.map { .move($0) }
            : pgnGame.moveTokens

        var variationDepth = 0

        for token in tokens {
            // Stop early once the prefix is satisfied; no remaining tokens matter.
            if moves.count >= pliesLimit { break }
            switch token {
            case .variationStart:
                variationDepth += 1
            case .variationEnd:
                if variationDepth > 0 { variationDepth -= 1 }
            case .move(let san):
                guard variationDepth == 0 else { continue }
                let (cleanedSan, annotation) = MoveAnnotation.extract(from: san)
                guard let move = parseMove(cleanedSan, in: position) else {
                    // Never skip a failed main-line token and continue from the
                    // wrong board. Discard the partial snapshot and report the
                    // exact point at which interpretation stopped.
                    return ParsedMainLine(
                        startPosition: startPosition,
                        moves: [],
                        diagnostics: pgnGame.diagnostics + [
                            .unparseableMainlineMove(
                                san: cleanedSan,
                                plyIndex: moves.count
                            )
                        ]
                    )
                }
                let positionBefore = position
                let notation = MoveGenerator.algebraicNotation(for: move, in: positionBefore)
                MoveGenerator.applyMoveUnchecked(&position, move)
                moves.append(MainLineMoveSnapshot(
                    move: move,
                    notation: notation,
                    positionBefore: positionBefore,
                    positionAfter: position,
                    annotation: annotation,
                    comment: nil,
                    engineEval: nil,
                    engineBestMoveUCI: nil,
                    clockSeconds: nil
                ))
            case .nag(let number):
                guard variationDepth == 0,
                      let annotation = MoveAnnotation.from(nag: number),
                      let lastIdx = moves.indices.last else { continue }
                let prev = moves[lastIdx]
                moves[lastIdx] = MainLineMoveSnapshot(
                    move: prev.move,
                    notation: prev.notation,
                    positionBefore: prev.positionBefore,
                    positionAfter: prev.positionAfter,
                    annotation: annotation,
                    comment: prev.comment,
                    engineEval: prev.engineEval,
                    engineBestMoveUCI: prev.engineBestMoveUCI,
                    clockSeconds: prev.clockSeconds
                )
            case .comment(let text):
                guard variationDepth == 0,
                      let lastIdx = moves.indices.last else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let parsed = parseEngineComment(trimmed)
                let prev = moves[lastIdx]
                let combinedComment: String?
                if let user = parsed.comment {
                    combinedComment = prev.comment.map { $0 + " " + user } ?? user
                } else {
                    combinedComment = prev.comment
                }
                let bestUCI: String?
                if let best = parsed.bestMove {
                    bestUCI = UCIParser.sanToUCI(best, in: prev.positionBefore) ?? best
                } else {
                    bestUCI = prev.engineBestMoveUCI
                }
                moves[lastIdx] = MainLineMoveSnapshot(
                    move: prev.move,
                    notation: prev.notation,
                    positionBefore: prev.positionBefore,
                    positionAfter: prev.positionAfter,
                    annotation: prev.annotation,
                    comment: combinedComment,
                    engineEval: parsed.eval ?? prev.engineEval,
                    engineBestMoveUCI: bestUCI,
                    clockSeconds: parsed.clockSeconds ?? prev.clockSeconds
                )
            }
        }

        return ParsedMainLine(
            startPosition: startPosition,
            moves: moves,
            diagnostics: pgnGame.diagnostics
        )
    }

    public nonisolated static func parseEngineComment(_ text: String) -> (eval: String?, bestMove: String?, comment: String?, clockSeconds: TimeInterval?) {
        var remaining = text
        var clockSeconds: TimeInterval?

        if let clkRange = remaining.range(of: #"\[%clk\s+(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]"#, options: .regularExpression) {
            let clkString = String(remaining[clkRange])
            remaining.removeSubrange(clkRange)
            remaining = remaining.trimmingCharacters(in: .whitespaces)
            let scanner = Scanner(string: clkString)
            scanner.charactersToBeSkipped = nil
            _ = scanner.scanUpToCharacters(from: .decimalDigits)
            if let h = scanner.scanInt() {
                _ = scanner.scanString(":")
                if let m = scanner.scanInt() {
                    _ = scanner.scanString(":")
                    if let s = scanner.scanDouble() {
                        clockSeconds = Double(h) * 3600 + Double(m) * 60 + s
                    }
                }
            }
        }

        let parts = remaining.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var eval: String?
        var bestMove: String?
        var commentParts: [String] = []

        for part in parts where !part.isEmpty {
            if part.hasPrefix("best ") {
                bestMove = String(part.dropFirst(5))
            } else if part.hasPrefix("+") || part.hasPrefix("-") || part.hasPrefix("0") || part.hasPrefix("M") {
                let isEval = part.allSatisfy { $0.isNumber || $0 == "." || $0 == "+" || $0 == "-" || $0 == "M" }
                if isEval {
                    eval = part
                } else {
                    commentParts.append(part)
                }
            } else {
                commentParts.append(part)
            }
        }

        let comment = commentParts.isEmpty ? nil : commentParts.joined(separator: "; ")
        return (eval, bestMove, comment, clockSeconds)
    }

    // Internal (not private) so the companion `PGN.swift` file's
    // `loadGame` path can reuse it without duplicating the table.
    public nonisolated static func pieceTypeFromChar(_ char: Character) -> PieceType? {
        switch char {
        case "K": .king
        case "Q": .queen
        case "R": .rook
        case "B": .bishop
        case "N": .knight
        default: nil
        }
    }

    nonisolated private static func parseTag(_ line: String) -> (String, String)? {
        // A well-formed PGN tag is `[Key "value"]`. Reject anything that
        // can't possibly satisfy that shape before chopping brackets, so
        // truncated inputs like `[` or `[]` don't crash `removeFirst` /
        // `removeLast`.
        guard line.count >= 2, line.first == "[", line.last == "]" else { return nil }
        var content = line
        content.removeFirst() // [
        content.removeLast()  // ]
        content = content.trimmingCharacters(in: .whitespaces)

        // §8.1 string token: the value starts after the first quote and ends
        // at the first UNESCAPED quote that follows — NOT the last quote on
        // the line. First/last-quote pairing folded any trailing junk after
        // the intended close (including junk containing quotes) into the
        // value. The scan unescapes as it goes: `\\` → `\`, `\"` → `"`; any
        // other backslash is kept literally (lenient — matches real-world
        // PGN that never escaped anything). Counterpart of the exporter's
        // escaping so export → import round-trips preserve values exactly.
        guard let quoteStart = content.firstIndex(of: "\"") else { return nil }

        var value = String()
        var idx = content.index(after: quoteStart)
        var closed = false
        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "\\" {
                let next = content.index(after: idx)
                if next < content.endIndex, content[next] == "\\" || content[next] == "\"" {
                    value.append(content[next])
                    idx = content.index(after: next)
                    continue
                }
                value.append(ch)
                idx = next
                continue
            }
            if ch == "\"" {
                closed = true
                break
            }
            value.append(ch)
            idx = content.index(after: idx)
        }
        // No closing quote → not a well-formed tag pair (same rejection the
        // old two-quote requirement gave unterminated values).
        guard closed else { return nil }

        let key = content[content.startIndex..<quoteStart].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    nonisolated private static func extractResult(from text: String) -> String? {
        let results = ["1-0", "0-1", "1/2-1/2", "*"]
        let tokens = text.split(separator: " ").map(String.init)
        return tokens.last(where: { results.contains($0) })
    }

    nonisolated private static func isResult(_ token: String) -> Bool {
        ["1-0", "0-1", "1/2-1/2", "*"].contains(token)
    }

    nonisolated private static func stripMoveNumberPrefix(_ word: String) -> String {
        var idx = word.startIndex
        while idx < word.endIndex && word[idx].isNumber {
            idx = word.index(after: idx)
        }
        guard idx > word.startIndex else { return word }
        let dotStart = idx
        while idx < word.endIndex && word[idx] == "." {
            idx = word.index(after: idx)
        }
        guard idx > dotStart else { return word }
        return String(word[idx...])
    }
}

// MARK: - PGN Exporter (token-level part)
//
// The `Game`/`MoveNode`-bound exporter methods (`export(game:)`,
// `moveText(for:)`, etc.) live in `PGN.swift`. The token-level
// serialization here is split out so it's reachable from
// SwiftData-only code paths (`Models/StoredGame.swift`'s StoredGame /
// PreparedGameData encoders) without dragging in the Game tree.
// (V1-REVIEW follow-up 2026-06-10 §3 rec #25: stale Item.swift /
// perf-harness references corrected)

public enum PGNExporter {

    public nonisolated static func tokenText(from pgnGame: PGNGame) -> String {
        if !pgnGame.moveTokens.isEmpty {
            return pgnGame.moveTokens.map { token in
                switch token {
                case .move(let san): san
                case .variationStart: "("
                case .variationEnd: ")"
                case .comment(let text): "{\(text)}"
                case .nag(let n): "$\(n)"
                }
            }.joined(separator: " ")
        }
        return pgnGame.moves.joined(separator: " ")
    }
}
