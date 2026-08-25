import Foundation

/// Structured issues discovered while parsing or materializing PGN input.
///
/// Lenient warnings can travel on parsed values; failures that cannot safely
/// produce a value also conform to `Error` for throwing APIs.
public enum PGNDiagnostic: Error, Equatable, Sendable {
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

public struct PGNGame: Identifiable, Sendable {
    public let id = UUID()
    public var tags: OrderedTags = OrderedTags()
    public var moves: [String] = []
    public var result: String? = nil
    public var moveTokens: [PGNToken] = []
    public var diagnostics: [PGNDiagnostic] = []

    public init() {}

    public var white: String { tags["White"] ?? "?" }
    public var black: String { tags["Black"] ?? "?" }
    public var date: String { tags["Date"] ?? "?" }
    public var event: String { tags["Event"] ?? "" }
    public var resultText: String { result ?? tags["Result"] ?? "*" }
    public var opening: String { tags["Opening"] ?? tags["ECO"] ?? "" }
    public var moveCount: Int { (moves.count + 1) / 2 }

    // Equatable is synthesized over (keys, values) — key ORDER participates in
    // equality, which is what tag-mirror change detection wants: any edit,
    // including a pure reorder, reads as "changed". (Game-wrap Stage 2 prep)
    public struct OrderedTags: Sendable, Equatable {
        private var keys: [String] = []
        private var values: [String: String] = [:]

        public init() {}

        public static let sevenTagRoster = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]

        public subscript(key: String) -> String? {
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

        public var orderedKeys: [String] {
            let roster = Self.sevenTagRoster.filter { values[$0] != nil }
            let rest = keys.filter { !Self.sevenTagRoster.contains($0) }
            return roster + rest
        }

        /// Raw insertion order used by lossless model snapshots. PGN export
        /// intentionally continues to use `orderedKeys`, which projects the
        /// canonical Seven Tag Roster ahead of supplemental tags.
        var insertionOrderedKeys: [String] { keys }

        public var isEmpty: Bool { keys.isEmpty }
    }
}

// MARK: - PGN Tokens

public enum PGNToken: Sendable {
    case move(String)
    case variationStart
    case variationEnd
    case comment(String)
    case nag(Int)
}

// MARK: - Sendable game-tree snapshots

/// A `Sendable` representation of a parsed PGN mainline. Carries everything
/// downstream consumers need without the main-actor-bound `Game` /
/// `MoveNode` class graph. Build this from a `Task.detached` on PGN text;
/// hop back to main only if you need to construct a live `Game` from it.
public struct MainLineMoveSnapshot: Sendable {
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

public struct ParsedMainLine: Sendable {
    public let startPosition: Position
    public let moves: [MainLineMoveSnapshot]
    public let diagnostics: [PGNDiagnostic]
}

// MARK: - PGN Parser (tokenize / parse / snapshot)
//
// `PGNParser` is split across two files. This one carries the pure
// tokenization and `Sendable`-snapshot path — used by anything that
// works off a PGN string but doesn't need to materialise a live `Game`
// tree. The companion file `PGN.swift` keeps the
// `Game`-bound `loadGame` overloads and the exporter.

public enum PGNParser {

    public static func parse(_ pgn: String) -> [PGNGame] {
        parse(pgn, maximumMoveTextBytes: 8 * 1024 * 1024)
    }

    /// Internal limit seam keeps oversized-input behavior directly testable
    /// without allocating multi-megabyte fixtures in the package test suite.
    static func parse(
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

        // stdlib split (Substrings share the parent buffer) instead of
        // Foundation `components(separatedBy: .newlines)` (a String copy per
        // line + CharacterSet). CRLF yields one fewer empty subsequence, which
        // the empty-line skip below absorbs.
        for line in pgn.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)

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

    public static func tokenize(_ moveText: String) -> [PGNToken] {
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

    public static func flatMoves(from tokens: [PGNToken]) -> [String] {
        var moves: [String] = []
        var depth = 0
        for token in tokens {
            switch token {
            case .variationStart: depth += 1
            case .variationEnd: depth = max(0, depth - 1)
            case .move(let san): if depth == 0 { moves.append(san) }
            default: break
            }
        }
        return moves
    }

    public static func parseMove(_ san: String, in position: Position) -> Move? {
        parseMove(san, in: position, legalMoves: MoveGenerator.legalMoves(for: position))
    }

    /// SAN → Move against a PRECOMPUTED legal-move list, so a decoder that has
    /// already generated the list (e.g. for `algebraicNotation`) does not
    /// regenerate it. Identical result to `parseMove(_:in:)`, which delegates
    /// here with a freshly generated list.
    public static func parseMove(_ san: String, in position: Position, legalMoves: [Move]) -> Move? {
        let cleaned = String(san.filter { $0 != "+" && $0 != "#" && $0 != "!" && $0 != "?" })
            .trimmingCharacters(in: CharacterSet.whitespaces)

        if cleaned == "O-O" || cleaned == "0-0" {
            let rank = position.activeColor == .white ? 0 : 7
            let target = Square(file: 6, rank: rank)
            return legalMoves.first { $0.piece == .king && $0.to == target && $0.isCastling }
        }
        if cleaned == "O-O-O" || cleaned == "0-0-0" {
            let rank = position.activeColor == .white ? 0 : 7
            let target = Square(file: 2, rank: rank)
            return legalMoves.first { $0.piece == .king && $0.to == target && $0.isCastling }
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

        // Promotion written WITHOUT '=' — PGN-lenient "exd8Q" and the
        // coordinate dialect the ChessUp mobile app exports ("a7b8q"). Safe to
        // strip here: a valid SAN token otherwise always ends in a rank digit
        // at this point (castling returned above; +/#/!? suffixes already
        // filtered), so a trailing piece letter can only be a promotion. The
        // candidate filter still requires an exact promotion match, so a
        // misread can never silently select a non-promotion move.
        if promotion == nil,
           remaining.count >= 3,
           let last = remaining.last {
            // `Character.uppercased()` returns a String; for a character whose
            // uppercase is multiple graphemes (e.g. "ß" → "SS"), `Character(_:)`
            // would trap on its single-grapheme precondition. Only a
            // single-scalar uppercase can be a promotion letter, so gate on that.
            let upper = last.uppercased()
            if upper.count == 1,
               let promoted = pieceTypeFromChar(Character(upper)),
               promoted != .king {
                promotion = promoted
                remaining = String(remaining.dropLast())
            }
        }

        guard let firstChar = remaining.first else { return nil }
        if firstChar.isUppercase {
            pieceType = pieceTypeFromChar(firstChar) ?? .pawn
            remaining = String(remaining.dropFirst())
        }

        remaining.removeAll { $0 == "x" }  // Foundation-free; avoids an intermediate string.

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

        let candidates = legalMoves.filter { move in
            guard move.piece == pieceType, move.to == target else { return false }
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

    /// Resolve the starting position shared by snapshot and live-tree PGN
    /// materialization. `nil` means a non-empty FEN tag was invalid.
    static func startingPosition(for pgnGame: PGNGame) -> Position? {
        guard let fen = pgnGame.tags["FEN"], !fen.isEmpty else {
            return Position.initial()
        }
        return Position(fen: fen)
    }

    /// Tokenize raw move text and parse its main line in one step.
    ///
    /// Equivalent to building a `PGNGame`, assigning `tokenize(moveText)` to
    /// its `moveTokens`, and calling ``parseMainLineSnapshot(from:pliesLimit:)``.
    ///
    /// - Parameters:
    ///   - moveText: PGN move text, without the tag pair section.
    ///   - pliesLimit: Stop collecting after this many plies. Useful when only
    ///     an opening prefix is wanted, since it avoids paying the full parse
    ///     cost of a long game. Defaults to no limit.
    public static func mainLineSnapshot(
        fromMoveText moveText: String,
        pliesLimit: Int = Int.max
    ) -> ParsedMainLine {
        var pgnGame = PGNGame()
        pgnGame.moveTokens = tokenize(moveText)
        return parseMainLineSnapshot(from: pgnGame, pliesLimit: pliesLimit)
    }

    /// Build a `Sendable` main-line snapshot from a parsed PGN game.
    ///
    /// Variations and tags are dropped; positions, comments, engine metadata
    /// and annotations are carried over. Because the result is a value type,
    /// this is the entry point for walking a game off the main actor — no
    /// `Game` object, and none of its reference-type confinement rules.
    ///
    /// - Parameters:
    ///   - pgnGame: A tokenized game. An invalid `FEN` tag fails closed: the
    ///     snapshot comes back with no moves rather than silently reinterpreted
    ///     against the initial position.
    ///   - pliesLimit: Stop collecting after this many plies. Defaults to no
    ///     limit.
    public static func parseMainLineSnapshot(
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
                // Generate the legal-move list once for both the SAN parse and
                // the canonical-notation derivation.
                let legal = MoveGenerator.legalMoves(for: position)
                guard let move = parseMove(cleanedSan, in: position, legalMoves: legal) else {
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
                let notation = MoveGenerator.algebraicNotation(for: move, in: positionBefore, legalMoves: legal)
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
                let trimmed = text.trimmingCharacters(in: CharacterSet.whitespaces)
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

    /// The `[%clk H:MM:SS(.f)]` pattern, compiled ONCE. Broadcast PGNs carry a
    /// clock tag on every ply, and recompiling this ICU pattern per ply is
    /// measurable on a whole-library replay. Sharing one instance across plies
    /// and threads is sound — NSRegularExpression is documented immutable and
    /// thread-safe for matching, and is `Sendable`, so a plain `static let`
    /// needs no annotation.
    private static let clockRegex = try! NSRegularExpression(
        pattern: #"\[%clk\s+(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]"#
    )

    /// The `[%eval …]` pattern: a signed decimal (`-1.42`) or a mate distance
    /// (`#-3`). Same sharing rationale as `clockRegex`.
    private static let evalRegex = try! NSRegularExpression(
        pattern: #"\[%eval\s+(#?[-+]?\d+(?:\.\d+)?)\]"#
    )

    /// Spell an evaluation the way the `[%eval …]` command wants it, or answer
    /// `nil` when it cannot be spelled that way at all.
    ///
    /// This is the INVERSE of the `[%eval …]` branch of ``parseEngineComment``
    /// and lives beside it so the pair cannot drift: `parseEngineComment`
    /// reports a mate distance as `M3` / `-M3` and a decimal exactly as
    /// written, and this turns those back into `#3` / `#-3` and the decimal.
    /// ``PGNExporter`` used to write the evaluation BARE (`{+0.34}`) next to a
    /// perfectly standard `[%clk 0:03:00]` in the same comment, so this
    /// library could re-read its own output while Lichess, ChessBase and
    /// python-chess could not see the evaluation at all.
    ///
    /// A decimal is required to have a decimal point with one or two places —
    /// which is what ``EvalFormat`` produces and what the readers in the field
    /// accept (python-chess's pattern is `[+-]?\d{0,10}\.\d{1,2}`). A leading
    /// `+` is kept: it is inside every one of those patterns.
    ///
    /// Returns `nil` for a mate with NO distance (the bare `M` / `-M` this
    /// app's annotation-restore path stores when the distance was not
    /// recoverable). `[%eval #]` is not a thing, and inventing a distance to
    /// fill the slot would publish a fact about the position that nothing
    /// measured — so callers emit those bare, exactly as before.
    public static func evalCommandArgument(for eval: String) -> String? {
        let trimmed = eval.trimmingCharacters(in: CharacterSet.whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var body = Substring(trimmed)
        var sign = ""
        if body.hasPrefix("-") {
            sign = "-"
            body = body.dropFirst()
        } else if body.hasPrefix("+") {
            body = body.dropFirst()
        }

        if body.hasPrefix("M") {
            let distance = body.dropFirst()
            // Bare `M` / `-M`: a mate is known, its distance is not.
            guard !distance.isEmpty, distance.allSatisfy({ $0.isNumber }) else { return nil }
            return "#\(sign)\(distance)"
        }

        // A decimal in pawns: digits, one point, one or two places.
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty, parts[0].allSatisfy({ $0.isNumber }),
              (1...2).contains(parts[1].count), parts[1].allSatisfy({ $0.isNumber })
        else { return nil }
        return trimmed
    }

    /// Split a PGN move comment into the engine annotations it carries and the
    /// prose that is left over.
    ///
    /// Two comment vocabularies are understood.
    ///
    /// **The `[%key value]` command syntax the PGN specification reserves.**
    /// ``PGNParser`` reads two of these: `[%clk H:MM:SS]` for a clock reading
    /// and `[%eval …]` for an evaluation, which is either a signed decimal in
    /// pawns (`[%eval -1.42]`) or a mate distance (`[%eval #-3]`). A mate
    /// distance is reported as `"M3"` / `"-M3"`; a decimal is reported exactly
    /// as written.
    ///
    /// **This library's own export format**, which
    /// ``PGNExporter/export(game:tags:)`` writes: an evaluation, then
    /// `best <SAN>`, then free prose, separated by semicolons —
    /// `{+0.34; best Nf3; solid}`. It round-trips what this library exports.
    ///
    /// Everything a comment carries that is neither of those comes back
    /// untouched in `comment`. In particular an evaluation token must contain a
    /// digit, so the Informant symbols (`+-`, `-+`, `+/-`) survive as prose
    /// rather than being read as evaluations.
    ///
    /// - Returns: the evaluation, the best move (SAN or UCI, as written), the
    ///   remaining prose, and the clock reading in seconds — each `nil` when
    ///   the comment did not carry it.
    public static func parseEngineComment(_ text: String) -> (eval: String?, bestMove: String?, comment: String?, clockSeconds: TimeInterval?) {
        var remaining = text
        var clockSeconds: TimeInterval?
        var taggedEval: String?

        // Fast-path: the `[%clk ...]` clock tag appears only in imported
        // broadcast/Lichess PGNs, never in engine eval / `; best` annotations.
        // `contains` is a cheap necessary condition for the regex to match, so
        // skipping it avoids compiling + scanning the regular expression on
        // every move comment during a full-library replay. Behavior is
        // identical — when the literal is absent the regex cannot match.
        if remaining.contains("[%clk") {
            let ns = remaining as NSString
            if let match = Self.clockRegex.firstMatch(
                in: remaining, range: NSRange(location: 0, length: ns.length)
            ) {
                // Groups 1/2/3 are h / mm / ss(.f) — read them directly instead
                // of re-scanning with a Foundation Scanner. Because the regex
                // already matched \d+:\d{2}:\d{2}(\.\d+)?, these always parse.
                if let h = Int(ns.substring(with: match.range(at: 1))),
                   let m = Int(ns.substring(with: match.range(at: 2))),
                   let s = Double(ns.substring(with: match.range(at: 3))) {
                    clockSeconds = Double(h) * 3600 + Double(m) * 60 + s
                }
                if let r = Range(match.range, in: remaining) {
                    remaining.removeSubrange(r)
                    remaining = remaining.trimmingCharacters(in: CharacterSet.whitespaces)
                }
            }
        }

        // The PGN-reserved `[%eval …]` command. Same `contains` fast path as
        // the clock tag above: absent literal ⇒ the regex cannot match.
        if remaining.contains("[%eval") {
            let ns = remaining as NSString
            if let match = Self.evalRegex.firstMatch(
                in: remaining, range: NSRange(location: 0, length: ns.length)
            ) {
                let value = ns.substring(with: match.range(at: 1))
                if value.hasPrefix("#") {
                    // Mate distance. `#-3` is mate against the side to move.
                    let distance = value.dropFirst()
                    taggedEval = distance.hasPrefix("-")
                        ? "-M\(distance.dropFirst())"
                        : "M\(distance.drop(while: { $0 == "+" }))"
                } else {
                    taggedEval = value
                }
                if let r = Range(match.range, in: remaining) {
                    remaining.removeSubrange(r)
                    remaining = remaining.trimmingCharacters(in: CharacterSet.whitespaces)
                }
            }
        }

        let parts = remaining.components(separatedBy: ";").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
        var eval: String? = taggedEval
        var bestMove: String?
        var commentParts: [String] = []

        for part in parts where !part.isEmpty {
            if part.hasPrefix("best ") {
                bestMove = String(part.dropFirst(5))
            } else if part.hasPrefix("+") || part.hasPrefix("-") || part.hasPrefix("0") || part.hasPrefix("M") {
                // An evaluation is made only of digits, a decimal point, a
                // sign, and the mate marker — AND must contain a digit. Without
                // the digit requirement the Informant symbols `+-` and `-+`
                // satisfy the character test and are silently eaten out of the
                // reader's prose.
                let isEval = part.contains(where: { $0.isNumber })
                    && part.allSatisfy { $0.isNumber || $0 == "." || $0 == "+" || $0 == "-" || $0 == "M" }
                if isEval {
                    // A `[%eval …]` tag, being the standardized spelling, wins
                    // over a bare token in the same comment.
                    if taggedEval == nil { eval = part }
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
    public static func pieceTypeFromChar(_ char: Character) -> PieceType? {
        switch char {
        case "K": .king
        case "Q": .queen
        case "R": .rook
        case "B": .bishop
        case "N": .knight
        default: nil
        }
    }

    private static func parseTag(_ line: String) -> (String, String)? {
        // A well-formed PGN tag is `[Key "value"]`. Reject anything that
        // can't possibly satisfy that shape before chopping brackets, so
        // truncated inputs like `[` or `[]` don't crash `removeFirst` /
        // `removeLast`.
        guard line.count >= 2, line.first == "[", line.last == "]" else { return nil }
        var content = line
        content.removeFirst() // [
        content.removeLast()  // ]
        content = content.trimmingCharacters(in: CharacterSet.whitespaces)

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

        let key = content[content.startIndex..<quoteStart].trimmingCharacters(in: CharacterSet.whitespaces)
        return (key, value)
    }

    private static func extractResult(from text: String) -> String? {
        let results = ["1-0", "0-1", "1/2-1/2", "*"]
        let tokens = text.split(separator: " ").map(String.init)
        return tokens.last(where: { results.contains($0) })
    }

    private static func isResult(_ token: String) -> Bool {
        ["1-0", "0-1", "1/2-1/2", "*"].contains(token)
    }

    private static func stripMoveNumberPrefix(_ word: String) -> String {
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
// serialization here is split out so value-oriented consumers can use it
// without dragging in the live Game tree.

public enum PGNExporter {

    public static func tokenText(from pgnGame: PGNGame) -> String {
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
