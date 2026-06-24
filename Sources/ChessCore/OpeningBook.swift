import Foundation

/// Thread-safe cache for `OpeningBook.continuations(for:)` results, keyed on
/// the same canonical position key the book itself uses. The continuations
/// data is fully determined by position so cached entries never need to be
/// invalidated; we just bound the cache to keep memory in check.
///
/// Uses `NSLock` (portable) rather than the Darwin-only `OSAllocatedUnfairLock`.
nonisolated private final class ContinuationsCache: @unchecked Sendable {
    static let shared = ContinuationsCache()
    private let lock = NSLock()
    private var storage: [String: [OpeningBook.BookMove]] = [:]
    private let countLimit = 4096

    func get(_ key: String) -> [OpeningBook.BookMove]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ key: String, _ value: [OpeningBook.BookMove]) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count >= countLimit {
            // Cheap eviction: drop ~10% of entries. Avoids a true LRU's
            // bookkeeping overhead for a workload (opening-book lookups)
            // that's already dominated by hot positions.
            let toRemove = max(1, storage.count / 10)
            for key in storage.keys.prefix(toRemove) {
                storage.removeValue(forKey: key)
            }
        }
        storage[key] = value
    }
}

public nonisolated struct OpeningBook: Sendable {
    public struct Entry: Sendable {
        public let eco: String
        public let name: String
        public let isTerminal: Bool
        public init(eco: String, name: String, isTerminal: Bool) {
            self.eco = eco
            self.name = name
            self.isTerminal = isTerminal
        }
    }

    public struct BookMove: Sendable {
        public let san: String
        public let openingName: String?
        public let eco: String?
        public init(san: String, openingName: String?, eco: String?) {
            self.san = san
            self.openingName = openingName
            self.eco = eco
        }
    }

    private var entries: [String: Entry] = [:]
    private var continuations: [String: [BookMove]] = [:]
    private var ecoNames: [String: String] = [:]

    public init() {}

    /// Build a book from precomputed data — the Apple app supplies
    /// `Bundle.main`'s `openings_precomputed.json`/`.plist`; Android supplies
    /// its own asset. Returns nil if the data can't be decoded.
    public init?(precomputedData data: Data, isPlist: Bool) {
        guard load(data: data, isPlist: isPlist) else { return nil }
    }

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var _shared = OpeningBook()

    /// The process-wide opening book. Empty until `configureShared` is called
    /// with the precomputed data — the Apple app and the Android app each wire
    /// it from their own resource bundle at startup. (The original app loaded
    /// this directly from `Bundle.main`; that lookup moved app-side so the core
    /// stays platform-agnostic.)
    public static var shared: OpeningBook {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        return _shared
    }

    /// Install the process-wide `shared` book from precomputed data.
    public static func configureShared(precomputedData data: Data, isPlist: Bool) {
        guard let book = OpeningBook(precomputedData: data, isPlist: isPlist) else { return }
        sharedLock.lock()
        _shared = book
        sharedLock.unlock()
    }

    public func lookup(_ position: Position) -> Entry? {
        entry(for: position)
    }

    /// Book entry for a position, retrying with the en-passant square
    /// dropped when it isn't actually capturable. The book keys positions
    /// by raw FEN, which records a phantom EP target after a double push
    /// even when no pawn can take it; a transposition that reaches a
    /// position via such a double push (e.g. 1.d4 e6 2.c4 d5) would carry
    /// that phantom EP and miss the entry keyed with no EP — the canonical
    /// 1.d4 d5 2.c4 e6 Queen's Gambit Declined. The fallback only adds
    /// matches the raw key missed; it never overrides a direct hit, so it
    /// can't misidentify a position that the book keys distinctly.
    /// (opening transposition fix 2026-06-16)
    private func entry(for position: Position) -> Entry? {
        let raw = Self.positionKey(position)
        if let entry = entries[raw] { return entry }
        let normalized = Self.epNormalizedKey(position)
        return normalized == raw ? nil : entries[normalized]
    }

    /// `positionKey` with the en-passant field reduced to a *capturable*
    /// EP square (or `-`); equals `positionKey` unless the position holds
    /// a phantom EP target. (opening transposition fix 2026-06-16)
    public static func epNormalizedKey(_ pos: Position) -> String {
        let fen = pos.fen
        let parts = fen.split(separator: " ")
        guard parts.count >= 4 else { return fen }
        let ep = pos.capturableEnPassantTarget?.algebraic ?? "-"
        return "\(parts[0]) \(parts[1]) \(parts[2]) \(ep)"
    }

    /// Canonicalize a stored position *key string* (not a live position)
    /// to the EP-normalized form. The repertoire subsystem stores and
    /// looks up by `epNormalizedKey`, but it only ever holds a key — not
    /// a `Position` — when migrating legacy rows or importing a backup,
    /// so it needs to normalize the string directly. Already-canonical
    /// keys (no en-passant square, or a genuinely capturable one) return
    /// unchanged, so this is idempotent and skips the FEN parse for the
    /// common "no EP" case. (repertoire transposition-awareness 2026-06-16)
    public static func epNormalizedKey(forStoredKey key: String) -> String {
        let parts = key.split(separator: " ")
        guard parts.count >= 4, parts[3] != "-" else { return key }
        guard let position = Position(fen: key + " 0 1") else { return key }
        return epNormalizedKey(position)
    }

    public func lookup(_ moves: [String]) -> Entry? {
        guard let position = Self.replayMoves(moves) else { return nil }
        return lookup(position)
    }

    public func openingName(forECO eco: String) -> String? {
        ecoNames[eco]
    }

    public func continuations(for position: Position) -> [BookMove] {
        let key = Self.positionKey(position)
        if let cached = ContinuationsCache.shared.get(key) { return cached }
        // Transposition fallback (phantom EP) — same reasoning as `entry`.
        guard let moves = continuations[key] ?? continuations[Self.epNormalizedKey(position)] else {
            // Cache the empty result too so we don't redo the dictionary
            // lookup on subsequent hits in non-book positions.
            ContinuationsCache.shared.set(key, [])
            return []
        }
        let legal = MoveGenerator.legalMoves(for: position)
        let resolved: [BookMove] = moves.map { move in
            if let m = legal.first(where: {
                MoveGenerator.algebraicNotation(for: $0, in: position, legalMoves: legal) == move.san
            }) {
                var pos = position
                MoveGenerator.applyMoveUnchecked(&pos, m)
                if let entry = entry(for: pos) {
                    return BookMove(san: move.san, openingName: entry.name, eco: entry.eco)
                }
            }
            return move
        }
        ContinuationsCache.shared.set(key, resolved)
        return resolved
    }

    public func continuations(after moves: [String]) -> [BookMove] {
        guard let position = Self.replayMoves(moves) else { return [] }
        return continuations(for: position)
    }

    public static func positionKey(_ pos: Position) -> String {
        let fen = pos.fen
        let parts = fen.split(separator: " ")
        guard parts.count >= 4 else { return fen }
        return "\(parts[0]) \(parts[1]) \(parts[2]) \(parts[3])"
    }

    private static func replayMoves(_ sans: [String]) -> Position? {
        var pos = Position.initial()
        for san in sans {
            guard let move = PGNParser.parseMove(san, in: pos) else { return nil }
            MoveGenerator.applyMoveUnchecked(&pos, move)
        }
        return pos
    }

    public func findPosition(forOpening name: String) -> Position? {
        let lower = name.lowercased()
        let key: String?
        if let exact = entries.first(where: { $0.value.name.lowercased() == lower })?.key {
            key = exact
        } else if let prefix = entries.first(where: { $0.value.name.lowercased().hasPrefix(lower) })?.key {
            key = prefix
        } else if let contains = entries.first(where: { lower.hasPrefix($0.value.name.lowercased()) })?.key {
            key = contains
        } else {
            key = nil
        }
        guard let key else { return nil }
        return Position(fen: key + " 0 1")
    }

    // MARK: - Pre-computed JSON loading

    private struct CodableEntry: Codable {
        let eco: String
        let name: String
        let isTerminal: Bool
    }

    private struct CodableBookMove: Codable {
        let san: String
        let openingName: String?
        let eco: String?
    }

    private struct CodableBook: Codable {
        let entries: [String: CodableEntry]
        let continuations: [String: [CodableBookMove]]
    }

    @discardableResult
    private mutating func load(data: Data, isPlist: Bool) -> Bool {
        let book: CodableBook
        do {
            book = isPlist
                ? try PropertyListDecoder().decode(CodableBook.self, from: data)
                : try JSONDecoder().decode(CodableBook.self, from: data)
        } catch {
            return false
        }

        entries = book.entries.mapValues { Entry(eco: $0.eco, name: $0.name, isTerminal: $0.isTerminal) }
        continuations = book.continuations.mapValues { moves in
            moves.map { BookMove(san: $0.san, openingName: $0.openingName, eco: $0.eco) }
        }

        var ecoMap: [String: String] = [:]
        for entry in entries.values {
            if let existing = ecoMap[entry.eco] {
                if entry.name.count < existing.count {
                    ecoMap[entry.eco] = entry.name
                }
            } else {
                ecoMap[entry.eco] = entry.name
            }
        }
        ecoNames = ecoMap
        return true
    }
}
